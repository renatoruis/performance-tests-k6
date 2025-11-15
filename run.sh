#!/bin/bash

# ================================================================
# SCRIPT DE EXECUÇÃO DE TESTES DE PERFORMANCE K6
# ================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ================================================================
# FUNÇÕES AUXILIARES
# ================================================================

print_header() {
    echo -e "\n${BLUE}=================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ================================================================
# VERIFICAR SE K6 ESTÁ INSTALADO
# ================================================================

check_k6() {
    if ! command -v k6 &> /dev/null; then
        print_error "k6 não está instalado!"
        echo ""
        echo "Para instalar:"
        echo "  macOS:   brew install k6"
        echo "  Linux:   sudo apt-get install k6"
        echo "  Windows: choco install k6"
        echo ""
        echo "Ou visite: https://k6.io/docs/get-started/installation/"
        exit 1
    fi
    print_success "k6 instalado: $(k6 version | head -n1)"
}

# ================================================================
# LISTAR CENÁRIOS DISPONÍVEIS
# ================================================================

list_scenarios() {
    print_header "CENÁRIOS DISPONÍVEIS"
    
    if [ ! -f "scenarios/config.json" ]; then
        print_error "Arquivo de configuração não encontrado!"
        exit 1
    fi
    
    echo "Cenários configurados:"
    echo ""
    
    # Tentar usar jq se disponível (melhor opção)
    if command -v jq &> /dev/null; then
        jq -r '.scenarios | to_entries[] | "  • \(.key)\n    \(.value.name)"' scenarios/config.json
    else        
        echo ""
        print_info "Dica: Instale 'jq' para ver descrições detalhadas dos cenários"
        echo "  macOS: brew install jq"
        echo "  Linux: sudo apt-get install jq"
    fi
    echo ""
}

# ================================================================
# EXECUTAR TESTE
# ================================================================

run_test() {
    local scenario=$1
    
    print_header "EXECUTANDO TESTE: $scenario"
    
    # Criar pasta de relatórios se não existir
    mkdir -p reports
    
    # Executar k6 (sempre da raiz do projeto)
    print_info "Iniciando teste..."
    cd "$(dirname "$0")" && k6 run -e SCENARIO="$scenario" src/main.js
    
    if [ $? -eq 0 ]; then
        print_success "Teste concluído com sucesso!"
        print_info "Relatórios salvos em: ./reports/"
        
        # Encontrar o relatório HTML mais recente
        latest_report=$(ls -t reports/*.html 2>/dev/null | head -n1)
        if [ -n "$latest_report" ]; then
            echo ""
            echo "Para visualizar o relatório:"
            echo "  ./run.sh report"
        fi
    else
        print_error "Teste falhou! Verifique os logs acima."
        exit 1
    fi
}

# ================================================================
# VISUALIZAR RELATÓRIO
# ================================================================

show_report() {
    cd "$(dirname "$0")"
    
    if [ -x "./utils/view-report.sh" ]; then
        ./utils/view-report.sh
    else
        # Fallback: abrir o mais recente diretamente
        latest_report=$(ls -t reports/*.html 2>/dev/null | head -n1)
        if [ -n "$latest_report" ]; then
            print_info "Abrindo relatório mais recente..."
            open "$latest_report" 2>/dev/null || xdg-open "$latest_report" 2>/dev/null || print_error "Não foi possível abrir o relatório automaticamente. Abra manualmente: $latest_report"
        else
            print_error "Nenhum relatório encontrado em ./reports/"
            echo ""
            echo "Execute um teste primeiro:"
            echo "  ./run.sh list"
            echo "  ./run.sh <cenario>"
            exit 1
        fi
    fi
}

# ================================================================
# FUNÇÃO PRINCIPAL
# ================================================================

main() {
    print_header "🚀 K6 PERFORMANCE TEST RUNNER"
    
    # Verificar se k6 está instalado
    check_k6
    
    # Se nenhum argumento, mostrar help
    if [ $# -eq 0 ]; then
        echo "Uso:"
        echo "  ./run.sh <cenário>     - Executa um cenário específico"
        echo "  ./run.sh list          - Lista todos os cenários disponíveis"
        echo "  ./run.sh report        - Abre o último relatório"
        echo "  ./run.sh help          - Mostra esta mensagem"
        echo ""
        echo "Exemplos:"
        echo "  ./run.sh get           - Executa cenário 'get'"
        echo "  ./run.sh report        - Abre último relatório"
        echo ""
        list_scenarios
        exit 0
    fi
    
    # Processar comando
    case "$1" in
        list)
            list_scenarios
            ;;
        report)
            show_report
            ;;
        help)
            main
            ;;
        *)
            run_test "$1"
            ;;
    esac
}

# Executar script
main "$@"

