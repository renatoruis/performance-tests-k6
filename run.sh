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
    
    # Ir para o diretório raiz do projeto
    cd "$(dirname "$0")"
    
    # Criar pasta de relatórios se não existir
    mkdir -p reports
    
    # Executar k6 (sempre da raiz do projeto)
    print_info "Iniciando teste..."
    k6 run -e SCENARIO="$scenario" src/main.js
    
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
    local mode=${1:-html}  # html ou terminal
    
    if [ "$mode" = "terminal" ] || [ "$mode" = "t" ]; then
        # Mostrar resumo no terminal
        # Listar relatórios disponíveis
        reports=($(ls -t reports/*-summary.json 2>/dev/null))
        
        if [ ${#reports[@]} -eq 0 ]; then
            print_error "Nenhum relatório encontrado em ./reports/"
            echo ""
            echo "Execute um teste primeiro:"
            echo "  ./run.sh <cenario>"
            exit 1
        fi
        
        local selected_json=""
        
        # Se houver mais de um relatório, permitir seleção
        if [ ${#reports[@]} -gt 1 ]; then
            echo ""
            echo -e "${BLUE}📊 RELATÓRIOS DISPONÍVEIS:${NC}"
            echo ""
            
            for i in "${!reports[@]}"; do
                local report="${reports[$i]}"
                local basename=$(basename "$report")
                local html_name="${basename%-summary.json}.html"
                local size=$(ls -lh "$report" | awk '{print $5}')
                local date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$report" 2>/dev/null || stat -c "%y" "$report" 2>/dev/null | cut -d'.' -f1)
                
                echo "  [$((i+1))] ${html_name}"
                echo "      Tamanho: $size | Modificado: $date"
                echo ""
            done
            
            echo -ne "${YELLOW}Digite o número do relatório para visualizar (Enter para o mais recente): ${NC}"
            read choice
            
            if [ -z "$choice" ]; then
                selected_json="${reports[0]}"
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#reports[@]} ]; then
                selected_json="${reports[$((choice-1))]}"
            else
                print_error "Opção inválida!"
                exit 1
            fi
        else
            selected_json="${reports[0]}"
        fi
        
        # Mostrar relatório selecionado
        if [ -n "$selected_json" ]; then
            print_header "📊 RESUMO DO RELATÓRIO"
            
            if command -v jq &> /dev/null; then
                echo ""
                print_info "Arquivo: $(basename $selected_json)"
                echo ""
                
                # Extrair métricas principais
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${YELLOW}📈 MÉTRICAS PRINCIPAIS${NC}"
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                
                jq -r '
                    "Total de requisições: \(.metrics.http_reqs.values.count // 0)",
                    "Taxa de requisições: \(.metrics.http_reqs.values.rate // 0 | tonumber | . * 100 / 100) req/s",
                    "Taxa de falhas: \((.metrics.http_req_failed.values.rate // 0 | tonumber * 100 | . * 100 / 100))%",
                    "",
                    "Duração da requisição (http_req_duration):",
                    "  • Média: \(.metrics.http_req_duration.values.avg // 0 | tonumber | . * 100 / 100)ms",
                    "  • Mínima: \(.metrics.http_req_duration.values.min // 0 | tonumber | . * 100 / 100)ms",
                    "  • Mediana (p50): \(.metrics.http_req_duration.values.med // 0 | tonumber | . * 100 / 100)ms",
                    "  • p(90): \(.metrics.http_req_duration.values."p(90)" // 0 | tonumber | . * 100 / 100)ms",
                    "  • p(95): \(.metrics.http_req_duration.values."p(95)" // 0 | tonumber | . * 100 / 100)ms",
                    "  • Máxima: \(.metrics.http_req_duration.values.max // 0 | tonumber | . * 100 / 100)ms",
                    "",
                    "VUs (Usuários Virtuais):",
                    "  • Mínimo: \(.metrics.vus.values.min // 0)",
                    "  • Máximo: \(.metrics.vus.values.max // 0)",
                    "",
                    "Duração do teste: \(.state.testRunDurationMs // 0 | tonumber / 1000)s"
                ' "$selected_json"
                
                echo ""
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                
                # Verificar thresholds
                echo ""
                echo -e "${YELLOW}✓ THRESHOLDS${NC}"
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                jq -r '
                    .metrics | to_entries[] | 
                    select(.value.thresholds != null) | 
                    .key as $metric |
                    .value.thresholds | to_entries[] |
                    if .value.ok then
                        "  ✅ \($metric): \(.key)"
                    else
                        "  ❌ \($metric): \(.key)"
                    end
                ' "$selected_json" || echo "  Nenhum threshold configurado"
                
                echo ""
                print_success "Para visualizar no navegador: ./run.sh report"
            else
                print_warning "Instale 'jq' para visualização formatada"
                echo ""
                echo "Para instalar jq:"
                echo "  macOS: brew install jq"
                echo "  Linux: sudo apt-get install jq"
                echo ""
                print_info "Mostrando JSON bruto..."
                cat "$selected_json"
            fi
        fi
    else
        # Abrir no navegador (comportamento padrão)
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
        echo "  ./run.sh report        - Abre o último relatório no navegador"
        echo "  ./run.sh report t      - Mostra resumo no terminal"
        echo "  ./run.sh help          - Mostra esta mensagem"
        echo ""
        echo "Exemplos:"
        echo "  ./run.sh get           - Executa cenário 'get'"
        echo "  ./run.sh report        - Abre relatório HTML"
        echo "  ./run.sh report t      - Resumo no terminal"
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
            show_report "${2:-html}"
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

