# sample-nodejs — Rafael DevOps / DevSecOps challenge

Repository: [https://github.com/eliranbt-commits/sample-nodejs](https://github.com/eliranbt-commits/sample-nodejs)

Small Express app packaged for Kubernetes: multi-stage Dockerfile, GitHub Actions (SAST, Trivy, Docker Hub), and ArgoCD GitOps from a **separate** repo: [gitops-sample-nodejs](https://github.com/eliranbt-commits/gitops-sample-nodejs).

## Why a Deployment (not a StatefulSet)

The app is stateless. It keeps nothing on local disk, has no sticky identity, and any pod can serve `/my-app`, `/ready`, `/live`, and `/metrics`. A Deployment is the right controller: pods are interchangeable and can be replaced freely.

A StatefulSet would be for ordered start/stop, stable network names, or per-pod volume claims (for example a database). None of that applies here.

## Why two Git repos

| Repo | Role |
| --- | --- |
| **This repo** (`sample-nodejs`) | App source, Dockerfile, CI (build / scan / push image) |
| [gitops-sample-nodejs](https://github.com/eliranbt-commits/gitops-sample-nodejs) | Helm chart + image tag. **Argo CD watches this one** |

- CI never runs `kubectl apply`. After a green scan it copies the chart and commits the new image tag **into the GitOps repo**; ArgoCD reconciles the cluster.
- App PRs cannot change what production deploys until CI pins a tag in GitOps.
- Chart templates still live here under `helm/sample-nodejs/` (local kind + `helm lint`). Each release copies them into GitOps so the two trees do not drift.

## App

| Path | Role |
| --- | --- |
| `GET /my-app` | Main response (`Hello, World!`) |
| `GET /about` | Static description |
| `GET /ready` | Readiness probe |
| `GET /live` | Liveness probe |
| `GET /metrics` | Prometheus metrics |
| `GET /classified` | Easter egg |

Port: `PORT` or `8080`. App sources live in `web-app/`. Run with `node web-app/app.js` (there is no `npm start`; `package.json` `main` is stale).

## Git workflow

Trunk-based development:

1. Feature branch → pull request into `main`.
2. PR pipeline: SAST, Helm lint, Hadolint, Docker build, Trivy. No push, no version bump.
3. Merge to `main`: patch bump (`1.0.0` → `1.0.1`), unless the commit message contains `bump:minor` or `bump:major`.
4. Image is scanned; HIGH/CRITICAL findings block the push.
5. Image is pushed to a **private** Docker Hub repo. CI commits the Helm pin to [gitops-sample-nodejs](https://github.com/eliranbt-commits/gitops-sample-nodejs) (Argo CD). It also mirrors `appVersion` / `image.tag` / `package.json` **in this repo** with `[skip ci]` so developers can see the current tag without opening Argo CD. That mirror is not what the cluster follows.

```mermaid
flowchart LR
  pr[PullRequest] --> sast[SAST]
  pr --> buildPr[DockerBuild]
  buildPr --> trivyPr[Trivy]
  main[MergeToMain] --> bump[VersionBump]
  bump --> sastMain[SAST]
  sastMain --> build[BuildAndPush]
  build --> trivy[TrivyFailOnHigh]
  trivy --> hub[DockerHubPrivate]
  hub --> gitops[CommitTagToGitOpsRepo]
  gitops --> argo[ArgoCD]
  argo --> k8s[kindCluster]
```

## CI/CD and DevSecOps

Workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

| Stage | Tool | Gate |
| --- | --- | --- |
| SAST | Semgrep (`p/javascript`, `p/nodejs`, `p/owasp-top-ten`) | Fail on ERROR |
| Dependency audit | `npm audit --audit-level=critical` | Fail on critical |
| Dockerfile lint | Hadolint | Fail on error |
| Chart lint | `helm lint` | Fail on error |
| Repo scan | Trivy filesystem | Fail on unfixed CRITICAL |
| Image scan | Trivy | Fail on unfixed HIGH/CRITICAL — **blocks deploy/push** |
| Build / push | Docker Buildx | Private Docker Hub |
| Deploy | Git commit of image tag in **gitops-sample-nodejs** (Argo) and a `[skip ci]` mirror here | ArgoCD, not kubectl from CI |

Unfixed OS findings are ignored (`ignore-unfixed: true`) so the gate tracks issues we can actually patch.

### GitHub secrets (required for `main`)

| Secret | Purpose |
| --- | --- |
| `DOCKERHUB_USERNAME` | Private Hub namespace |
| `DOCKERHUB_TOKEN` | Hub access token with push access |
| `GITOPS_TOKEN` | GitHub PAT with **Contents: Read and write** on [gitops-sample-nodejs](https://github.com/eliranbt-commits/gitops-sample-nodejs). Default `GITHUB_TOKEN` cannot push to another repo. |

Create a Docker Hub repository [eliranb1978/eliran-apps-images](https://hub.docker.com/r/eliranb1978/eliran-apps-images). In GitHub: **Settings → Secrets and variables → Actions**, add `DOCKERHUB_USERNAME` (`eliranb1978`), `DOCKERHUB_TOKEN`, and `GITOPS_TOKEN`.

Seed the GitOps repo once (chart must exist before the first version job): copy `helm/` from this repo, or push `/home/user/RAFAEL/gitops-sample-nodejs`. If the GitOps repo is private, also give Argo CD a PAT (repo read) as a repository credential.

## Helm chart

Path in **this** repo (local + CI lint): [`helm/sample-nodejs/`](helm/sample-nodejs/)

Path Argo CD uses: [gitops-sample-nodejs `helm/sample-nodejs/`](https://github.com/eliranbt-commits/gitops-sample-nodejs/tree/main/helm/sample-nodejs)

- Deployment, Service, Ingress (`ingressClassName: nginx`)
- Readiness `/ready` and liveness `/live` with different delay/period
- ConfigMap for `PORT`; Secret template present but disabled (the app has no secret)
- CPU/memory requests and limits
- Non-root `securityContext`
- `imagePullSecrets` for the private registry overlay

| Values file | Use |
| --- | --- |
| `values.yaml` | Local kind (`sample-nodejs:local`, `pullPolicy: Never`) |
| `values-gitops.yaml` | ArgoCD / Docker Hub (CI updates `repository` and `tag`) |

Local install (image already loaded into kind):

```bash
kind load docker-image sample-nodejs:local --name play
helm upgrade --install sample-nodejs ./helm/sample-nodejs \
  --set image.repository=sample-nodejs \
  --set image.tag=local \
  --set image.pullPolicy=Never
```

## ArgoCD on local kind

Cluster context expected: `kind-play`.

```bash
export DOCKERHUB_USERNAME=your-hub-user
export DOCKERHUB_TOKEN=your-hub-token
bash scripts/bootstrap-kind-gitops.sh
```

That script creates namespaces, the `dockerhub` pull secret, installs Argo CD, and applies [`argocd/application.yaml`](argocd/application.yaml) (source = **gitops-sample-nodejs**).

Push a green `main` build so GitOps `values-gitops.yaml` is pinned to a real tag on `eliranb1978/eliran-apps-images`. Then re-apply the Application if it still pointed at the old repo:

```bash
kubectl apply -f argocd/application.yaml
```

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n sample-nodejs get pods,svc,ingress
curl -H 'Host: sample-nodejs.local' http://localhost/my-app
```

If ingress-nginx is not installed on kind, either install it or port-forward the Service:

```bash
kubectl -n sample-nodejs port-forward svc/sample-nodejs 8080:80
curl http://localhost:8080/my-app
```

## Screenshot / evidence checklist

Take these for submission:

1. GitHub Actions green run (SAST + Trivy + push).
2. `kubectl get pods` — `sample-nodejs` Running `1/1`.
3. ArgoCD UI: Application `Synced` / `Healthy`.
4. Browser or curl of `/my-app` through Ingress (or port-forward).
5. Docker Hub showing tags on [eliranb1978/eliran-apps-images](https://hub.docker.com/r/eliranb1978/eliran-apps-images).

## Layout

```text
.
├── Dockerfile
├── web-app/
│   ├── app.js
│   ├── package.json
│   └── package-lock.json
├── .github/workflows/ci.yml
├── argocd/application.yaml          # points Argo CD at gitops-sample-nodejs
├── helm/sample-nodejs/              # chart source; CI copies into GitOps on release
├── scripts/
│   ├── next-version.sh
│   ├── apply-version.sh
│   └── bootstrap-kind-gitops.sh
└── README.md
```
