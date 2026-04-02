const express = require("express");

const app = express();

const ALLOC_MB = Number.parseInt(process.env.ALLOC_MB || "100", 10);
const APP_NAME = process.env.APP_NAME || "memory-lab-app";
const PORT = Number.parseInt(process.env.PORT || "8000", 10);

const memoryHolder = [];
let startupTime = "";
let requestCount = 0;
let errorCount = 0;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function allocateMemory() {
  for (let i = 0; i < ALLOC_MB; i += 1) {
    memoryHolder.push(Buffer.alloc(1024 * 1024));
    await sleep(10);

    if ((i + 1) % 10 === 0) {
      console.log(`allocated ${i + 1} / ${ALLOC_MB} MB`);
    }
  }
}

app.use((req, res, next) => {
  void req;
  requestCount += 1;

  res.on("finish", () => {
    if (res.statusCode >= 500) {
      errorCount += 1;
      console.log(`5xx response: ${res.statusCode}`);
    }
  });

  next();
});

app.get("/health", (req, res) => {
  void req;
  res.status(200).json({
    status: "ok",
    app: APP_NAME,
    alloc_mb: ALLOC_MB,
    startup_time: startupTime,
    request_count: requestCount,
  });
});

app.get("/ping", (req, res) => {
  void req;
  res.status(200).send("pong");
});

app.get("/", (req, res) => {
  void req;
  res.status(200).json({
    app: APP_NAME,
    alloc_mb: ALLOC_MB,
    uptime_since: startupTime,
  });
});

app.get("/stats", (req, res) => {
  void req;
  res.status(200).json({
    app: APP_NAME,
    alloc_mb: ALLOC_MB,
    startup_time: startupTime,
    memory_chunks: memoryHolder.length,
    request_count: requestCount,
    error_count: errorCount,
    now: new Date().toISOString(),
  });
});

async function start() {
  console.log(`APP=${APP_NAME}  ALLOC_MB=${ALLOC_MB}  started=${new Date().toISOString()}`);

  await allocateMemory();

  startupTime = new Date().toISOString();
  console.log(`startup complete: ${ALLOC_MB} MB held at ${startupTime}`);

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`listening on 0.0.0.0:${PORT}`);
  });
}

start();
