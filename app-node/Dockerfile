FROM node:20-slim AS deps

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:20-slim AS runner

WORKDIR /app

ENV WEBSITES_PORT=8000

COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY server.js ./

EXPOSE 8000

CMD ["node", "server.js"]
