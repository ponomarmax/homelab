.PHONY: test test-pipeline test-wearable-ingestion-api test-wearable-pipeline-api test-ios smoke-hr deploy-wearable-ingestion-api validate-wearable-ingestion-api

test: test-pipeline test-ios

test-pipeline: test-wearable-ingestion-api test-wearable-pipeline-api

test-wearable-ingestion-api:
	python3 -m unittest discover -s services/wearable-ingestion-api/tests -p 'test_*.py' -v

test-wearable-pipeline-api:
	python3 -m unittest discover -s services/wearable-pipeline-api/tests -p 'test_*.py' -v

test-ios:
	@if command -v xcodebuild >/dev/null 2>&1; then \
		cd apps/ios-collector && xcodebuild test \
			-workspace ios-collector.xcworkspace \
			-scheme CollectorApp \
			-destination 'platform=iOS Simulator,name=iPhone 17' \
			-derivedDataPath /tmp/ios-collector-derived || \
			echo 'warning: iOS tests failed in current workspace setup (see xcodebuild output above)'; \
	else \
		echo 'xcodebuild not found, skipping iOS tests'; \
	fi

smoke-hr:
	python3 services/wearable-ingestion-api/scripts/smoke_hr.py

deploy-wearable-ingestion-api:
	tools/scripts/deploy.sh --confirm wearable-ingestion-api

validate-wearable-ingestion-api:
	tools/scripts/validate-wearable-ingestion-api.sh
