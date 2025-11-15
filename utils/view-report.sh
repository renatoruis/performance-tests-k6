#!/bin/bash

# ================================================================
# SCRIPT PARA VISUALIZAR RELATÓRIOS HTML DO K6
# ================================================================

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Verificar se existem relatórios
if [ ! -d "reports" ] || [ -z "$(ls -A reports/*.html 2>/dev/null)" ]; then
    print_warning "Nenhum relatório HTML encontrado!"
    echo ""
    echo "Execute um teste primeiro:"
    echo "  ./run.sh <cenário>"
    exit 1
fi

# Se um argumento for passado, tentar abrir esse relatório específico
if [ $# -eq 1 ]; then
    if [ -f "reports/$1" ]; then
        print_info "Abrindo relatório: $1"
        open "reports/$1"
        exit 0
    elif [ -f "$1" ]; then
        print_info "Abrindo relatório: $1"
        open "$1"
        exit 0
    else
        print_warning "Relatório não encontrado: $1"
        echo ""
    fi
fi

# Listar relatórios disponíveis
echo ""
echo -e "${BLUE}📊 RELATÓRIOS DISPONÍVEIS:${NC}"
echo ""

counter=1
declare -a reports

while IFS= read -r report; do
    filename=$(basename "$report")
    size=$(du -h "$report" | cut -f1)
    modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$report" 2>/dev/null || stat -c "%y" "$report" 2>/dev/null | cut -d'.' -f1)
    
    reports+=("$report")
    echo "  [$counter] $filename"
    echo "      Tamanho: $size | Modificado: $modified"
    echo ""
    
    ((counter++))
done < <(ls -t reports/*.html)

# Se houver apenas um relatório, abrir automaticamente
total_reports=$((counter - 1))

if [ $total_reports -eq 1 ]; then
    print_info "Abrindo o único relatório disponível..."
    open "${reports[0]}"
    print_success "Relatório aberto no navegador!"
    exit 0
fi

# Perguntar qual relatório abrir
echo -ne "${YELLOW}Digite o número do relatório para abrir (Enter para o mais recente): ${NC}"
read choice

if [ -z "$choice" ]; then
    choice=1
fi

# Validar escolha
if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $total_reports ]; then
    selected_report="${reports[$((choice - 1))]}"
    print_info "Abrindo: $(basename "$selected_report")"
    open "$selected_report"
    print_success "Relatório aberto no navegador!"
else
    print_warning "Escolha inválida!"
    exit 1
fi

