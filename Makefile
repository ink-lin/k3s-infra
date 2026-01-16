# --- 變數定義 ---
HELM_BIN    := helm
KUBECTL_BIN := kubectl
APP         ?= dify

# --- 路徑解析 ---
APP_DIR     := ./apps/$(APP)
# 判斷是 Helm 還是純 Kustomize (檢查是否有 values-override.yaml)
IS_HELM     := $(shell [ -f $(APP_DIR)/values-override.yaml ] && echo "yes" || echo "no")

CHART_DIR := ./charts/$(APP)

ifneq ("$(wildcard $(CHART_DIR)/charts/$(APP)/Chart.yaml)","")
    CHART_DIR := $(CHART_DIR)/charts/$(APP)
endif

OUTPUT_FILE := $(APP_DIR)/base-rendered.yaml
VALUES_FILE := $(APP_DIR)/values-override.yaml
NAMESPACE   ?= $(APP)

.PHONY: help template diff apply clean ns

help: ## 顯示說明 (可指定 APP=name)
	@echo "\033[33mUsage: make [target] APP=[app_name]\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

ns: ## 確保 Namespace 存在
	@$(KUBECTL_BIN) create namespace $(NAMESPACE) --dry-run=client -o yaml | $(KUBECTL_BIN) apply -f -

template: ## 產出 Helm Template (僅限 Helm App)
	@if [ "$(IS_HELM)" = "yes" ]; then \
		echo "=> Rendering Helm template for [\033[32m$(APP)\033[0m]..."; \
		$(HELM_BIN) template $(APP) $(CHART_DIR) --namespace $(NAMESPACE) -f $(VALUES_FILE) > $(OUTPUT_FILE); \
	else \
		echo "=> [\033[33m$(APP)\033[0m] is a pure Kustomize app, skipping Helm template."; \
	fi

diff: ns template ## 預覽差異
	@echo "=> Diffing [\033[32m$(APP)\033[0m]..."
	$(KUBECTL_BIN) diff -k $(APP_DIR) || true

apply: ns template ## 部署服務
	@echo "=> Applying [\033[32m$(APP)\033[0m]..."
	$(KUBECTL_BIN) apply -k $(APP_DIR)

destroy: ## 徹底移除部署的資源 (APP=xxx)
	@echo "=> Destroying [\033[31m$(APP)\033[0m] resources..."
	$(KUBECTL_BIN) delete -k $(APP_DIR) --ignore-not-found

clean: ## 清除本地生成的 base-rendered.yaml
	rm -f $(APP_DIR)/base-rendered.yaml

clean-all: ## 清理所有 app 的產出 YAML
	@for app in $$(ls ./apps); do \
		$(MAKE) clean APP=$$app; \
	done