# Red Doors opener — built in-cluster (oc start-build opener --from-dir=openers).
FROM docker.io/library/node:24-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src ./src
# OpenShift runs this under restricted-v2 with an arbitrary UID; nothing is written to the image.
USER 1001
ENV NODE_ENV=production PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
