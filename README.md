# Testes de Performance - k6

Sistema de testes de performance usando k6.

## Instalação

```bash
# macOS
brew install k6

# Linux
sudo apt-get install k6
```

## Como Usar

### 1️⃣ Configure seu cenário

Edite `scenarios/config.json`:

```json
{
  "api": {
    "baseUrl": "http://localhost:8888"
  },
  "auth": {
    "enabled": true,
    "tokenUrl": "http://localhost:8080/realms/...",
    "clientId": "seu-client",
    "clientSecret": "seu-secret"
  },
  "scenarios": {
    "meu-teste": {
      "name": "Meu Teste",
      "method": "GET",
      "endpoint": "/api/endpoint",
      "requireAuth": true,
      "vus": 10,
      "duration": "1m",
      "timeout": "5s",
      "expectedStatus": 200
    }
  }
}
```

### 2️⃣ Execute o teste

```bash
# Listar cenários disponíveis
./run.sh list

# Executar um cenário
./run.sh meu-teste
```

### 3️⃣ Veja o resultado

```bash
# Abre automaticamente o relatório mais recente
./run.sh report
```

## Configurações do Cenário

| Parâmetro | Descrição | Exemplo |
|-----------|-----------|---------|
| `name` | Nome descritivo | `"Teste de Carga"` |
| `method` | Método HTTP | `"GET"` ou `"POST"` |
| `endpoint` | Endpoint da API | `"/api/users"` |
| `requireAuth` | Requer autenticação? | `true` / `false` |
| `vus` | Usuários virtuais | `100` |
| `duration` | Duração do teste | `"5m"`, `"30s"` |
| `timeout` | Timeout das requisições | `"10s"` |
| `expectedStatus` | Status HTTP esperado | `200` |
| `sleep` | Pausa entre requisições (seg) | `0.5` |

### Configurações Avançadas

```json
{
  "meu-teste-avancado": {
    "method": "POST",
    "endpoint": "/api/data",
    "customPayload": {
      "campo": "valor",
      "timestamp": "{{timestamp}}"
    },
    "stages": [
      {"duration": "1m", "target": 100},
      {"duration": "3m", "target": 500},
      {"duration": "1m", "target": 0}
    ],
    "thresholds": {
      "http_req_duration": ["p(99)<300"],
      "req_fail_rate": ["rate<0.01"]
    }
  }
}
```

**Placeholders disponíveis:**
- `{{timestamp}}` - Timestamp atual em millisegundos
- `{{random}}` - Número aleatório

## Comandos Disponíveis

```bash
./run.sh list           # Lista todos os cenários
./run.sh <cenario>      # Executa um cenário
./run.sh report         # Abre o último relatório
./run.sh help           # Mostra ajuda
```

## Estrutura do Projeto

```
├── run.sh              # Executor principal
├── README.md           # Esta documentação
├── scenarios/
│   └── config.json     # Suas configurações
├── reports/            # Relatórios gerados
└── src/                # Arquivos internos (não mexer)
```

## Métricas Principais

- **http_req_duration** - Tempo total da requisição
- **http_req_waiting** - Time to First Byte (TTFB)
- **http_req_failed** - Taxa de falhas
- **http_reqs** - Total de requisições
- **vus** - Usuários virtuais ativos

Percentis: p(50), p(90), p(95), p(99)

## Troubleshooting

### Erro de autenticação
Verifique `clientId` e `clientSecret` em `scenarios/config.json`

### Teste falhou (threshold excedido)
Ajuste os thresholds ou reduza a carga (VUs)

### Token expirando
Para testes longos (>30min), adicione `"refreshToken": true` no cenário

## Exemplo Completo

```bash
# 1. Configure seu cenário em scenarios/config.json
# 2. Liste os cenários disponíveis
./run.sh list

# 3. Execute o teste
./run.sh meu-teste

# 4. Veja o relatório
./run.sh report
```

---

**Suporte:** Equipe de Performance/DevOps - Mercantil
