class_name ProfileOrdinarySession
extends RefCounted
## An issuer activity can leave an unknown amount of volatile ordinary earnings.
## One pair of ledger markers covers the activity without recording each accrual.

enum ReopenStatus { UNAVAILABLE, CLEAR, POSSIBLE_EXPOSURE }

const Commit := ProfileStore.CommitResult

var _profile: ProfileStore
var _identity: String
var _start: ProfileMutation
var _finish: ProfileMutation
var _open := false


static func reopen_status(profile: ProfileStore) -> ReopenStatus:
	if profile == null:
		return ReopenStatus.UNAVAILABLE
	var latest := profile.latest_ordinary_session()
	if latest.status == Commit.MISSING:
		return ReopenStatus.CLEAR
	if latest.status == Commit.COMMITTED:
		if latest.id.ends_with("/open"):
			return ReopenStatus.POSSIBLE_EXPOSURE
		if latest.id.ends_with("/settled"):
			return ReopenStatus.CLEAR
	return ReopenStatus.UNAVAILABLE


static func prepare(profile: ProfileStore, run: String, rules: String, catalog: String) -> ProfileOrdinarySession:
	if (profile == null or not ProfileMutation.valid_id(run)
			or not ProfileMutation.valid_id(rules) or not ProfileMutation.valid_id(catalog)):
		return null
	var head := profile.checkpoint()
	if head.is_empty() or head.generation == Quantity.INT_MAX:
		return null
	var session_number: int = head.generation + 1
	var scope := JSON.stringify([profile.identity(), run, rules, catalog]).sha256_text()
	var id := ProfileStore.ORDINARY_SESSION_PREFIX + "%019d/%s" % [session_number, scope]
	var session := ProfileOrdinarySession.new()
	session._profile = profile
	session._identity = profile.identity()
	session._start = _marker(id + "/open", rules, catalog)
	session._finish = _marker(id + "/settled", rules, catalog)
	return session


func uses(profile: ProfileStore) -> bool:
	return profile != null and profile == _profile and profile.identity() == _identity


func tracks(earnings: OrdinaryCurrency) -> bool:
	return earnings.issued_by(_profile)


func is_open() -> bool:
	return _open and uses(_profile)


func open() -> bool:
	if not uses(_profile):
		return false
	_open = _open or _commit(_start)
	return _open


## Call after admission is sealed and every ordinary batch is confirmed.
func settle() -> bool:
	if not is_open():
		return false
	# Query the closing operation first to resolve any uncertain prior close.
	var settled := _profile.lookup(_finish.id)
	if settled.status == Commit.COMMITTED:
		return settled.digest == _finish.record().sha256_text()
	if settled.status != Commit.MISSING:
		return false
	var active := _profile.lookup(_start.id)
	return (active.status == Commit.COMMITTED and active.digest == _start.record().sha256_text()
		and _commit(_finish))


func _commit(marker: ProfileMutation) -> bool:
	return _profile.commit_confirmed(marker).status in [Commit.COMMITTED, Commit.DUPLICATE]


static func _marker(id: String, rules: String, catalog: String) -> ProfileMutation:
	var marker := ProfileMutation.new()
	marker.id = id
	marker.rules = rules
	marker.catalog = catalog
	return marker
