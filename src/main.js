import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { htmlReport } from "https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js";
import { textSummary } from "https://jslib.k6.io/k6-summary/0.0.1/index.js";

// ================================================================
// IMPORTAÇÃO DE CONFIGURAÇÃO
// ================================================================
// k6 usa o diretório do script como base, então precisamos subir um nível
const CONFIG = JSON.parse(open(__ENV.CONFIG_PATH || '../scenarios/config.json'));
const SCENARIO = __ENV.SCENARIO || 'default';
const scenario = CONFIG.scenarios[SCENARIO] || CONFIG.scenarios['default'];

// ================================================================
// MÉTRICAS CUSTOMIZADAS
// ================================================================
const totalDuration = new Trend('total_duration');
const waitDuration = new Trend('waiting_ttfb');
const blocked = new Trend('blocked');
const dns = new Trend('dns');
const tcp = new Trend('tcp');
const tls = new Trend('tls');
const receiving = new Trend('receiving');
const sending = new Trend('sending');
const reqFailRate = new Rate('req_fail_rate');
const slowRequests = new Counter('req_slow_over_threshold');

// ================================================================
// FUNÇÃO AUXILIAR PARA SANITIZAÇÃO
// ================================================================
function safe(x) {
  return (typeof x === "number" && isFinite(x)) ? x : 0;
}

// ================================================================
// OPÇÕES DO TESTE (DINÂMICAS)
// ================================================================
export const options = {
  // Cenários de carga
  ...(scenario.executor === 'constant-arrival-rate' ? {
    scenarios: {
      constant_load: {
        executor: 'constant-arrival-rate',
        rate: scenario.rate,
        timeUnit: scenario.timeUnit || '1s',
        duration: scenario.duration,
        preAllocatedVUs: scenario.preAllocatedVUs || 50,
        maxVUs: scenario.maxVUs || 1000,
      },
    },
  } : scenario.stages ? {
    stages: scenario.stages,
  } : {
    vus: scenario.vus || 10,
    duration: scenario.duration || '1m',
  }),

  // Thresholds
  thresholds: {
    http_req_duration: scenario.thresholds?.http_req_duration || ['p(99)<250'],
    req_fail_rate: scenario.thresholds?.req_fail_rate || ['rate<0.005'],
    req_slow_over_threshold: scenario.thresholds?.req_slow_over_threshold || ['count<1000'],
  },

  // SSL/TLS - Bypass de verificação de certificado (similar ao curl -k)
  insecureSkipTLSVerify: scenario.insecureSkipTLSVerify || CONFIG.insecureSkipTLSVerify || false,
};

// ================================================================
// CONFIGURAÇÕES DE AMBIENTE
// ================================================================
const BASE_URL = CONFIG.api.baseUrl;
const AUTH_ENABLED = CONFIG.auth.enabled !== false; // default true para backward compatibility
const KC_TOKEN_URL = CONFIG.auth.tokenUrl || '';
const CLIENT_ID = CONFIG.auth.clientId || '';
const CLIENT_SECRET = CONFIG.auth.clientSecret || '';

// ================================================================
// CONTROLE DE TOKEN (PARA CENÁRIOS SEM SETUP)
// ================================================================
let cachedToken = '';
let tokenExpiresAt = 0;

// ================================================================
// FUNÇÃO PARA OBTER TOKEN
// ================================================================
function getToken() {
  const payload = {
    grant_type: "client_credentials",
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET
  };

  const res = http.post(KC_TOKEN_URL, payload, {
    timeout: "10s",
  });

  check(res, {
    'token status 200': r => r.status === 200,
    'token has access_token': r => r.json('access_token') !== undefined,
  });

  if (res.status !== 200) {
    console.error(`❌ Erro ao obter token: ${res.status}`);
    throw new Error("Falha ao obter token");
  }

  const data = res.json();
  
  // Atualiza cache se estiver usando refresh automático
  if (scenario.refreshToken) {
    tokenExpiresAt = Date.now() + (data.expires_in - 5) * 1000;
  }

  return data.access_token;
}

// ================================================================
// SETUP - EXECUTA UMA VEZ ANTES DO TESTE
// ================================================================
export function setup() {
  console.log(`\n🚀 Iniciando teste: ${SCENARIO}`);
  console.log(`📊 Configuração: ${JSON.stringify(scenario, null, 2)}\n`);
  
  // Se autenticação não é requerida, pula token
  if (scenario.requireAuth === false || !AUTH_ENABLED) {
    console.log('ℹ️  Autenticação desabilitada para este cenário\n');
    return { token: null, requireAuth: false };
  }
  
  // Se o cenário requer refresh automático, não pega token no setup
  if (scenario.refreshToken) {
    return { token: null, requireAuth: true };
  }

  return { token: getToken(), requireAuth: true };
}

// ================================================================
// FUNÇÃO PARA GERAR PAYLOAD (PARA POSTS)
// ================================================================
function generatePayload() {
  // Se tem payload customizado, usa ele
  if (scenario.customPayload) {
    let payload = JSON.stringify(scenario.customPayload);
    // Substituir placeholders
    payload = payload.replace(/\{\{timestamp\}\}/g, Date.now().toString());
    payload = payload.replace(/\{\{random\}\}/g, Math.random().toString());
    return payload;
  }
  
  // Fallback para payload padrão baseado em tamanho
  const sizeKB = scenario.payloadSizeKB || 25;
  const base = 'x'.repeat(1024);
  return JSON.stringify({ dadosEntrada: base.repeat(sizeKB) });
}

// ================================================================
// FUNÇÃO PRINCIPAL DE TESTE
// ================================================================
export default function (data) {
  // Gerenciamento de token
  let token = null;
  const requiresAuth = data.requireAuth !== false && scenario.requireAuth !== false && AUTH_ENABLED;
  
  if (requiresAuth) {
    if (scenario.refreshToken) {
      if (!cachedToken || Date.now() >= tokenExpiresAt) {
        cachedToken = getToken();
      }
      token = cachedToken;
    } else {
      token = data.token;
    }
  }

  const headers = {
    ...(requiresAuth && token && { Authorization: `Bearer ${token}` }),
    ...(scenario.method === 'POST' && { 'Content-Type': 'application/json' }),
  };

  // Executar requisição
  let res;
  let expectedStatus = scenario.expectedStatus || 200;
  
  // Suporte para método MIXED (múltiplos endpoints)
  if (scenario.method === 'MIXED' && scenario.endpoints) {
    // Escolher endpoint baseado em peso (weight)
    const random = Math.random();
    let cumulative = 0;
    let selectedEndpoint = scenario.endpoints[0];
    
    for (const endpoint of scenario.endpoints) {
      cumulative += endpoint.weight || 0.5;
      if (random <= cumulative) {
        selectedEndpoint = endpoint;
        break;
      }
    }
    
    const url = `${BASE_URL}${selectedEndpoint.endpoint}`;
    expectedStatus = selectedEndpoint.expectedStatus || 200;
    
    if (selectedEndpoint.method === 'POST') {
      let payload = JSON.stringify(selectedEndpoint.payload || {});
      payload = payload.replace(/\{\{timestamp\}\}/g, Date.now().toString());
      payload = payload.replace(/\{\{random\}\}/g, Math.random().toString());
      
      res = http.post(url, payload, {
        headers: { ...headers, 'Content-Type': 'application/json' },
        timeout: scenario.timeout || "10s"
      });
    } else {
      res = http.get(url, {
        headers,
        timeout: scenario.timeout || "10s"
      });
    }
  }
  // Métodos simples (GET ou POST)
  else {
    const url = `${BASE_URL}${scenario.endpoint || '/v1/testes'}`;
    
    if (scenario.method === 'POST') {
      const payload = generatePayload();
      res = http.post(url, payload, {
        headers,
        timeout: scenario.timeout || "10s"
      });
    } else {
      res = http.get(url, {
        headers,
        timeout: scenario.timeout || "10s"
      });
    }
  }

  // ================================================================
  // COLETA DE MÉTRICAS
  // ================================================================
  totalDuration.add(safe(res.timings.duration));
  waitDuration.add(safe(res.timings.waiting));
  dns.add(safe(res.timings.dns));
  tcp.add(safe(res.timings.connecting));
  tls.add(safe(res.timings.tls_handshaking));
  sending.add(safe(res.timings.sending));
  receiving.add(safe(res.timings.receiving));
  blocked.add(safe(res.timings.blocked));

  const slowThreshold = scenario.slowThreshold || 2000;
  if (safe(res.timings.duration) > slowThreshold) {
    slowRequests.add(1);
  }

  // ================================================================
  // VALIDAÇÕES
  // ================================================================
  const acceptableStatuses = scenario.acceptableStatuses || [expectedStatus];
  
  const ok = check(res, {
    [`${scenario.method} status ok`]: r => acceptableStatuses.includes(r.status),
  });

  if (!ok) {
    reqFailRate.add(1);
    console.error(
      `❌ Falha ${scenario.method}: status=${res.status}, ` +
      `esperado=${acceptableStatuses.join(' ou ')}, ` +
      `tempo=${safe(res.timings.duration)}ms, ` +
      `body=${res.body?.substring(0, 200)}`
    );
  } else {
    reqFailRate.add(0);
    
    // Log de rate limiting (429) para debug
    if (res.status === 429) {
      console.log(`⚠️  Rate limit atingido (esperado em teste de carga)`);
    }
  }

  // Sleep opcional entre requisições
  if (scenario.sleep) {
    sleep(scenario.sleep);
  }
}

// ================================================================
// GERAÇÃO DE RELATÓRIO HTML
// ================================================================
export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/:/g, '-').split('.')[0];
  const reportName = `report-${SCENARIO}-${timestamp}`;

  // k6 usa o diretório do script como base, então precisamos subir um nível
  const reportsPath = __ENV.REPORTS_PATH || '../reports';
  return {
    [`${reportsPath}/${reportName}.html`]: htmlReport(data),
    stdout: textSummary(data, { indent: " ", enableColors: true }),
    [`${reportsPath}/${reportName}-summary.json`]: JSON.stringify(data, null, 2),
  };
}

