# Paid node Firestore rule hardening

이 PR에서 정상 독자 앱은 더 이상 `storyPacks/{packId}/nodes`를 직접 읽지 않는다.
`fetchReaderStoryNodes` Cloud Function이 무료/구매/preview 권한을 서버에서 판정한 뒤
`liveSnapshot`만 반환하고, 홈의 `collectionGroup('nodes')` 조회도
`storyPacks.publishedNodeCount` 서버 집계값으로 대체됐다.

따라서 배포 시 `firestore.rules`의 node read를 다음 원칙으로 잠가야 한다.

1. `storyPacks/{packId}/nodes/{nodeId}` 직접 read: 작가 본인 또는 admin만 허용.
2. `{path=**}/nodes/{nodeId}` collectionGroup read: admin만 허용.
3. 독자는 노드 문서를 직접 읽지 않고 `fetchReaderStoryNodes`만 사용.

현재 체크인된 rules의 broad published-node read를 그대로 배포하면 정상 앱은 안전한
서버 경로를 쓰더라도 악의적인 클라이언트가 Firestore SDK로 직접 published 문서를
읽는 우회가 남는다. 실제 Rules 배포 전에는 이 PR을 Ready로 전환하지 않는다.

기존 팩은 배포 직후 admin 계정으로 `backfillPublishedNodeCounts`를 한 번 호출해야
홈 노출/진행률 계산이 즉시 정상화된다. 그 이후에는 `maintainPublishedNodeCount`
트리거가 값을 자동 유지한다.
