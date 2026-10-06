# Red Doors API — built in-cluster (oc start-build red-doors-api --from-dir=api).
FROM docker.io/library/node:24-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src ./src
USER 1001
ENV NODE_ENV=production PORT=3001 AUDIT_PORT=9090
EXPOSE 3001 9090
CMD ["node", "src/server.js"]
