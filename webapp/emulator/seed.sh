#!/usr/bin/env bash
# Seeds the local Auth + Firestore emulators (their rules) with three test members for the web app:
#   admin@test.local  (ADMIN, active)   dan@test.local (member, prefers driver)   pam@test.local (member, passenger)
# Password for all three: see PW below (emulator only, never a real account).
set -euo pipefail
PROJECT=gen-lang-client-0717949368
AUTH=http://localhost:9199
FS="http://localhost:8185/v1/projects/$PROJECT/databases/(default)/documents"
PW=test123456
NOW=$(date +%s%3N)

mk_user() { # email name -> uid
  curl -s "$AUTH/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$PW\",\"displayName\":\"$2\",\"returnSecureToken\":true}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["localId"])'
}
s() { echo "{\"stringValue\":\"$1\"}"; }
i() { echo "{\"integerValue\":\"$1\"}"; }
d() { echo "{\"doubleValue\":$1}"; }
b() { echo "{\"booleanValue\":$1}"; }

put_user() { # uid name email emp dept role status mode seats township
  curl -s -X PATCH "$FS/users/$1" -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' -d "{\"fields\":{
    \"uid\":$(s "$1"),\"name\":$(s "$2"),\"email\":$(s "$3"),\"employeeId\":$(s "$4"),\"department\":$(s "$5"),
    \"role\":$(s "$6"),\"accountStatus\":$(s "$7"),\"phone\":$(s "0300123456$RANDOM"),\"townshipLocation\":$(s "${10}"),
    \"currentMode\":$(s "$8"),\"defaultRolePreference\":$(s "$8"),\"defaultDriverSeats\":$(i $9),\"muteUntilTimestamp\":$(i 0),
    \"isPasswordChanged\":$(b true),\"createdAt\":$(i $NOW),\"blockedAt\":$(i 0),\"blockedBy\":$(s ""),\"blockReason\":$(s ""),
    \"removedAt\":$(i 0),\"removedBy\":$(s ""),\"removeReason\":$(s ""),\"approvalRequestedAt\":$(i $NOW),\"approvedAt\":$(i $NOW),
    \"approvedBy\":$(s "seed"),\"consentAcceptedAt\":$(i $NOW),\"consentVersion\":$(i 1),\"privacyNoticeVersion\":$(i 1),
    \"totalCo2SavedKg\":$(d 0.0),\"totalCompletedRides\":$(i 0)}}" > /dev/null
}

A=$(mk_user admin@test.local "Awaiz Admin"); put_user "$A" "Awaiz Admin" admin@test.local FFL-00001 Administration ADMIN ACTIVE PASSENGER 3 EMs
D=$(mk_user dan@test.local "Dan Driver");    put_user "$D" "Dan Driver" dan@test.local FFL-00002 Maintenance USER ACTIVE DRIVER 3 "C-Type"
P=$(mk_user pam@test.local "Pam Passenger"); put_user "$P" "Pam Passenger" pam@test.local FFL-00003 HSE USER ACTIVE PASSENGER 3 EMs
curl -s -X PATCH "$FS/systemConfig/sustainability" -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
  -d "{\"fields\":{\"baselineDistanceKm\":$(d 3.0),\"co2FactorKgPerKm\":$(d 0.12),\"approverDisplayName\":$(s "Awaiz Admin"),\"approverEmail\":$(s admin@test.local)}}" > /dev/null
echo "seeded: admin=$A dan=$D pam=$P (password: $PW)"
