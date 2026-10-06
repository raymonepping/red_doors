# Red Doors UI — built in-cluster (oc start-build red-doors-ui --from-dir=ui).
FROM docker.io/library/node:24-slim AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npx nuxt build

FROM docker.io/library/node:24-slim
WORKDIR /app
COPY --from=build /src/.output ./.output
USER 1001
ENV NODE_ENV=production PORT=3000 HOST=0.0.0.0
EXPOSE 3000
CMD ["node", ".output/server/index.mjs"]
