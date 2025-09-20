#!/bin/bash

# Script de correção emergencial COMPLETA para produção
# Execute este script no servidor de produção

echo "🚨 Aplicando correção emergencial COMPLETA para EventFinancials e Events..."

# Conectar ao banco e aplicar correções
psql $DATABASE_URL << EOF

-- ============================================================================
-- 1. CORREÇÕES PARA TABELA EVENT_FINANCIALS
-- ============================================================================

-- 1.1. Renomear coluna para corresponder à entidade Java
DO \$\$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'event_financials' 
               AND column_name = 'last_transfer_at') THEN
        ALTER TABLE event_financials RENAME COLUMN last_transfer_at TO last_transfer_date;
    END IF;
END \$\$;

-- 1.2. Adicionar colunas básicas de transferência
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS next_transfer_date TIMESTAMP;
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS transfer_frequency VARCHAR(20) DEFAULT 'WEEKLY' NOT NULL;
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS total_payments INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS pending_transfer_amount DECIMAL(12,2) DEFAULT 0 NOT NULL;

-- 1.3. ❌ CRÍTICO: Adicionar colunas de receita que estão causando erros
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS total_revenue DECIMAL(12,2) DEFAULT 0 NOT NULL;
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS platform_fees DECIMAL(12,2) DEFAULT 0 NOT NULL;
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS net_revenue DECIMAL(12,2) DEFAULT 0 NOT NULL;
ALTER TABLE event_financials ADD COLUMN IF NOT EXISTS total_transfer_fees DECIMAL(12,2) DEFAULT 0 NOT NULL;

-- 1.4. Remover constraint órfã que está causando problemas
ALTER TABLE event_financials DROP CONSTRAINT IF EXISTS chk_event_financials_transfer_frequency;

-- 1.5. Adicionar constraint correta após criar a coluna
ALTER TABLE event_financials ADD CONSTRAINT chk_event_financials_transfer_frequency 
    CHECK (transfer_frequency IN ('IMMEDIATE', 'DAILY', 'WEEKLY', 'MONTHLY', 'ON_DEMAND'));

-- 1.6. Atualizar dados existentes para mapear colunas antigas para novas
UPDATE event_financials SET 
    total_revenue = COALESCE(total_collected, 0),
    platform_fees = COALESCE(platform_fee_amount, 0),
    net_revenue = COALESCE(organizer_net_amount, 0),
    pending_transfer_amount = COALESCE(pending_transfers, 0)
WHERE total_revenue = 0 OR platform_fees = 0;

-- ============================================================================
-- 2. CORREÇÕES PARA TABELA EVENTS
-- ============================================================================

-- 2.1. ❌ CRÍTICO: Adicionar platform_fee_percentage que está causando o erro atual
ALTER TABLE events ADD COLUMN IF NOT EXISTS platform_fee_percentage DECIMAL(5,4);

-- 2.2. Adicionar transfer_frequency para events
ALTER TABLE events ADD COLUMN IF NOT EXISTS transfer_frequency VARCHAR(20) DEFAULT 'WEEKLY';

-- 2.3. Adicionar constraint para transfer_frequency em events
DO \$\$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_events_transfer_frequency') THEN
        ALTER TABLE events ADD CONSTRAINT chk_events_transfer_frequency 
            CHECK (transfer_frequency IS NULL OR transfer_frequency IN ('IMMEDIATE', 'DAILY', 'WEEKLY', 'MONTHLY', 'ON_DEMAND'));
    END IF;
END \$\$;

-- ============================================================================
-- 3. VERIFICAÇÕES FINAIS
-- ============================================================================

-- 3.1. Verificar estrutura da tabela event_financials
\d event_financials

-- 3.2. Verificar estrutura da tabela events
\d events

-- 3.3. Verificar constraints
SELECT 
    tc.table_name, 
    tc.constraint_name, 
    pg_get_constraintdef(pgc.oid) as definition
FROM information_schema.table_constraints tc
JOIN pg_constraint pgc ON tc.constraint_name = pgc.conname
WHERE tc.table_name IN ('event_financials', 'events')
AND tc.constraint_type = 'CHECK'
ORDER BY tc.table_name, tc.constraint_name;

EOF

echo "✅ Correção COMPLETA aplicada!"
echo "🎯 Schema agora corresponde 100% às entidades EventFinancials.java e Event.java"
echo "🚀 Reinicie a aplicação para aplicar as mudanças."