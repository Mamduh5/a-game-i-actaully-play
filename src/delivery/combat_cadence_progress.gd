class_name CombatCadenceProgress
extends RefCounted
## Exact accrued progress for one independently authored rate domain.

var _period_ticks: int
var _progress := QuantityFraction.from_amount(Quantity.from_count(0))


static func create(period_ticks: int) -> CombatCadenceProgress:
	if period_ticks <= 0:
		return null
	var clock := CombatCadenceProgress.new()
	clock._period_ticks = period_ticks
	return clock


func retune(period_ticks: int) -> bool:
	if period_ticks <= 0:
		return false
	_period_ticks = period_ticks
	return true


## Count completed periods and retain the remaining exact fraction. The
## run decides how to dispatch that many events on its authoritative frontier.
func advance(elapsed_ticks: int) -> int:
	if elapsed_ticks < 0:
		return -1
	var accrued := QuantityFraction.create(Quantity.from_count(elapsed_ticks), Quantity.from_count(_period_ticks))
	if accrued == null:
		return -1
	var next := _progress.plus(accrued)
	if next == null:
		return -1
	var counts := Quantity.divide_integers(next.numerator, next.divisor)
	if counts.size() != 2 or counts[0] == null or counts[0].uses_limbs or counts[1] == null:
		return -1
	var remainder := QuantityFraction.create(counts[1], next.divisor)
	if remainder == null:
		return -1
	_progress = remainder
	return counts[0].native_at_scale(0)
