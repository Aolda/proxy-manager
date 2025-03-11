FROM node:22-alpine AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

FROM base AS build

WORKDIR /app
COPY proxy-manager-frontend/ ./

RUN pnpm install --frozen-lockfile
RUN pnpm run build

FROM nginx:stable-alpine

COPY rootfs/ /
COPY --from=build /app/dist /app/frontend

VOLUME ["/data"]

ARG PUID=1000
ARG PGID=1000
ENV PUID=${PUID}
ENV PGID=${PGID}

RUN chmod +x /docker-entrypoint.sh

EXPOSE 80 81 443

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.license="MIT"
LABEL org.label-schema.name="aolda-proxy-manager"
LABEL org.label-schema.description="Aolda Proxy Manager"
LABEL org.label-schema.url="https://git.ajou.ac.kr/aolda/proxy-manager"
LABEL org.label-schema.vcs-url="https://git.ajou.ac.kr/aolda/proxy-manager.git"
