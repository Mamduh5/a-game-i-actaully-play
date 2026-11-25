extends GutTest
## HARNESS SELF-TEST — intentionally failing. Never part of the default suite.
##
## tools/run_gut.ps1 -Probe runs only this directory and expects a nonzero exit,
## proving that a failing assertion propagates to the process exit code (QAS L03,
## TDS dependency register: "assert the failing-process exit in WP01").


func test_intentional_failure_propagates() -> void:
	assert_eq(1, 2, "intentional failure: the harness must report this run as failed")
