#!/bin/bash

# --------------------------
# Configuration
# --------------------------
PROJECT_NAME="devops-project"
DESKTOP_DIR="$HOME/Desktop"
PROJECT_ROOT="$DESKTOP_DIR/$PROJECT_NAME"
K8S_DIR="$PROJECT_ROOT/kubernetes"
HELM_DIR="$PROJECT_ROOT/helm/my-app"
SERVICE_MESH_DIR="$PROJECT_ROOT/service-mesh"
ARGOCD_DIR="$PROJECT_ROOT/argocd"

# --------------------------
# Cleanup Previous Setup
# --------------------------
echo "Cleaning up previous installation..."
rm -rf "$PROJECT_ROOT"
minikube delete >/dev/null 2>&1

# --------------------------
# Create Folder Structure
# --------------------------
echo "Creating project structure..."
mkdir -p "$K8S_DIR" "$HELM_DIR" "$SERVICE_MESH_DIR" "$ARGOCD_DIR"

# --------------------------
# Generate Kubernetes Manifests
# --------------------------
cat <<EOF > "$K8S_DIR/deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
      annotations:
        sidecar.istio.io/inject: "true"
    spec:
      containers:
      - name: frontend
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: db_host
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
EOF



cat <<EOF > "$K8S_DIR/backend-deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
      annotations:
        sidecar.istio.io/inject: "true"
    spec:
      containers:
      - name: backend
        image: your-backend-image:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
EOF

# Database StatefulSet
cat <<EOF > "$K8S_DIR/postgres-statefulset.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: dev
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:13
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
EOF



# Similar blocks for other YAML files (service.yaml, ingress.yaml, etc.)

# --------------------------
# Generate Helm Charts
# --------------------------
helm create "$HELM_DIR" >/dev/null

# Enhanced Helm Chart
cat <<EOF > "$HELM_DIR/values-prod.yaml"
replicaCount: 4
image:
  repository: your-prod-image
  tag: stable
env:
  db_host: "postgres-prod-service"
resources:
  limits:
    cpu: "2000m"
    memory: "2Gi"
EOF


# --------------------------
# Add Security Configurations
# --------------------------
# Generate real base64 secrets
echo -n "admin" | base64 > /tmp/username
echo -n "secret123!" | base64 > /tmp/password

cat <<EOF > "$K8S_DIR/secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: dev
type: Opaque
data:
  username: $(cat /tmp/username)
  password: $(cat /tmp/password)
EOF

# --------------------------
# Generate Service Mesh Configs
# --------------------------
cat <<EOF > "$SERVICE_MESH_DIR/virtualservice.yaml"
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: backend
spec:
  hosts:
  - "*"
  http:
  - route:
    - destination:
        host: frontend
        subset: v1
      weight: 90
    - destination:
        host: frontend
        subset: v2
      weight: 10
EOF

# --------------------------
# Enhanced Argo CD Setup
# --------------------------
cat <<EOF > "$ARGOCD_DIR/prod-application.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $PROJECT_NAME-prod
spec:
  project: default
  source:
    repoURL: https://github.com/your-repo.git
    path: helm/my-app
    targetRevision: HEAD
    helm:
      valueFiles:
      - values-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF


# --------------------------
# Add Rollback Simulation
# --------------------------
echo -e "\n# Simulate Rollback\nkubectl set image deployment/frontend frontend=broken-image -n dev\nargocd app sync $PROJECT_NAME" >> "$PROJECT_ROOT/README.md"

# --------------------------
# Generate README
# --------------------------
cat <<EOF > "$PROJECT_ROOT/README.md"
# DevOps Project Setup

## Access Endpoints
- Frontend: http://your-app.com
- Argo CD UI: http://localhost:8080

## Management Commands
- View pods: kubectl get pods -n dev
- Access Istio dashboard: istioctl dashboard kiali
EOF

# --------------------------
# Cluster Setup
# --------------------------
echo "Starting Minikube cluster..."
minikube start --driver=docker
eval $(minikube docker-env)

# --------------------------
# Deploy to Kubernetes
# --------------------------
echo "Deploying to Kubernetes..."
kubectl create namespace dev
kubectl create namespace prod
kubectl apply -f "$K8S_DIR" -n dev

# --------------------------
# Service Mesh Setup
# --------------------------
echo "Installing Istio..."
istioctl install --set profile=demo -y
kubectl label namespace dev istio-injection=enabled

# --------------------------
# Argo CD Setup
# --------------------------
echo "Installing Argo CD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# --------------------------
# Final Output
# --------------------------
echo "Project setup completed successfully!"
echo "Project location: $PROJECT_ROOT"
echo "Access Argo CD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"