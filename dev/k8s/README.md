# Vibekube Local Kubernetes

This is a tiny disposable Kubernetes cluster for developing Vibekube against a real Kubernetes API.

It uses [kind](https://kind.sigs.k8s.io/) on top of Docker and creates:

- `vibekube-demo/echo-web`: two small nginx pods behind a service.
- `vibekube-demo/log-counter`: a pod that writes a log line every two seconds.
- `vibekube-demo/tiny-heartbeat`: a CronJob that creates short-lived job pods every two minutes.
- Demo ConfigMaps and Secrets referenced through pod `env`, `envFrom`, `configMapKeyRef`, and `secretKeyRef` so the resource inspector has real data to render.

## Start

```sh
dev/k8s/scripts/start.sh
```

The script creates or reuses the `vibekube-dev` kind cluster and switches kubectl to:

```sh
kind-vibekube-dev
```

The demo web service is exposed at:

```sh
http://localhost:18080
```

## Try It

```sh
kubectl -n vibekube-demo get pods -w
kubectl -n vibekube-demo logs -f deploy/log-counter
kubectl -n vibekube-demo describe svc echo-web
kubectl -n vibekube-demo describe pod -l app.kubernetes.io/name=echo-web
kubectl -n vibekube-demo get configmap,secret
kubectl -n vibekube-demo get jobs
```

## Status

```sh
dev/k8s/scripts/status.sh
```

## Stop

```sh
dev/k8s/scripts/stop.sh
```

This deletes the local cluster. Running `start.sh` recreates it from scratch.
