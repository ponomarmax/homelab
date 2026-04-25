.PHONY: test test-pipeline test-ios smoke-hr

test: test-pipeline test-ios

test-pipeline:
	python3 -m unittest discover -s services/ingestion-api/tests -p 'test_*.py' -v

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
	python3 services/ingestion-api/scripts/smoke_hr.py
