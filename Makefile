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

.PHONY: help template diff diff-copy apply destroy clean clean-all ns

help: ## 顯示說明 (可指定 APP=name)
	@echo "\033[33mUsage: make [target] APP=[app_name]\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

ns: ## 確保 Namespace 存在
	@$(KUBECTL_BIN) create namespace $(NAMESPACE) --dry-run=client -o yaml | $(KUBECTL_BIN) apply -f -

template: ## 產出 Helm Template (僅限 Helm App)
	@if [ "$(IS_HELM)" = "yes" ]; then \
		if [ -f "$(CHART_DIR)/Chart.yaml" ]; then \
			if [ ! -d "$(CHART_DIR)/charts" ] || [ -z "$$(ls -A $(CHART_DIR)/charts 2>/dev/null)" ]; then \
				echo "=> Dependencies missing or empty in $(CHART_DIR), running \033[33mhelm dependency build\033[0m..."; \
				$(HELM_BIN) dependency build $(CHART_DIR) || exit 1; \
			fi; \
		fi; \
		echo "=> Rendering Helm template for [\033[32m$(APP)\033[0m]..."; \
		$(HELM_BIN) template $(APP) $(CHART_DIR) --namespace $(NAMESPACE) -f $(VALUES_FILE) > $(OUTPUT_FILE); \
	else \
		echo "=> [\033[33m$(APP)\033[0m] is a pure Kustomize app, skipping Helm template."; \
	fi

diff: ns template ## 預覽差異
	@echo "=> Diffing [\033[32m$(APP)\033[0m]..."
	$(KUBECTL_BIN) diff -k $(APP_DIR) || true

diff-copy: ## 執行 diff 並使用 xclip 複製到剪貼簿
	@echo "=> Running diff for [\033[32m$(APP)\033[0m] and copying via xclip..."
	@$(MAKE) -s diff APP=$(APP) | xclip -selection clipboard
	@echo "=> \033[32mDone!\033[0m Diff output is now in your X11 clipboard."

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

# --- Sealed Secrets 變數 ---
SECRET_BKP_DIR     := ./secret-backups
# 預設還原檔案名稱，也可以在執行時透過 SEALED_KEY=xxx 指定
SEALED_KEY         ?= $(SECRET_BKP_DIR)/master-key.yaml
SEALED_NS          := kube-system

.PHONY: seal-secret backup-secrets restore-secrets

seal-secret: ## 互動式加密多個 Key-Value
	@read -p "Enter Secret Name (e.g., postgres-creds 登入賬密等, gemini-secret 金鑰憑證等): " NAME; \
	read -p "Enter Key-Value pairs (e.g., --from-literal=user=admin --from-literal=pass=123): " PAIRS; \
	mkdir -p $(APP_DIR)/secrets; \
	$(KUBECTL_BIN) create secret generic $$NAME $$PAIRS -n $(NAMESPACE) --dry-run=client -o yaml | \
	kubeseal --format yaml > $(APP_DIR)/secrets/$$NAME.sealed.yaml
	@echo "=> \033[32mCreated $$NAME.sealed.yaml with multiple keys\033[0m"

backup-secrets: ## [Security] 備份 Sealed Secrets 私鑰到本地 (請務必妥善保管此檔案)
	@mkdir -p $(SECRET_BKP_DIR)
	@echo "=> Exporting Sealed Secrets Master Key from namespace [\033[32m$(SEALED_NS)\033[0m]..."
	@$(KUBECTL_BIN) get secret -n $(SEALED_NS) -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > $(SEALED_KEY)
	@echo "=> \033[32mBackup completed\033[0m: $(SEALED_KEY)"
	@echo "\033[33m[WARNING] DO NOT commit this file to Git! Add it to .gitignore.\033[0m"

restore-secrets: ## [Security] 從備份檔案還原 Sealed Secrets 私鑰
	@if [ ! -f "$(SEALED_KEY)" ]; then \
		echo "\033[31mError: Backup file $(SEALED_KEY) not found!\033[0m"; \
		exit 1; \
	fi
	@echo "=> Preparing namespace [\033[32m$(SEALED_NS)\033[0m]..."
	@$(KUBECTL_BIN) create namespace $(SEALED_NS) --dry-run=client -o yaml | $(KUBECTL_BIN) apply -f -
	@echo "=> Restoring Master Key from $(SEALED_KEY)..."
	@$(KUBECTL_BIN) apply -f $(SEALED_KEY)
	@echo "=> \033[32mRestoration successful.\033[0m Please install/restart Sealed Secrets Controller now."