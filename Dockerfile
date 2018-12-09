#
# Use multi stage build so require docker version higher 17.05.
#
FROM golang:1.11 AS development
ARG name=
ARG repository=
RUN apt-get update -y
RUN apt-get install -y doxygen doxygen-gui graphviz
WORKDIR /go/src/${repository}
COPY Makefile ./
RUN make setup
CMD ["/bin/true"]

FROM development AS builder
COPY Gopkg.toml Gopkg.lock ./
RUN make vendor
COPY . .
RUN make build
CMD ["/bin/true"]

FROM alpine
ARG name=
ARG repository=
ENV ADDR 8080
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /go/src/${repository}/${name} ./app
ENTRYPOINT ["./app"]
