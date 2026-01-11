helm install dify-local dify/dify \
  -n dify \
  --create-namespace \
  -f helm/dify/values-k3s-local.yaml
