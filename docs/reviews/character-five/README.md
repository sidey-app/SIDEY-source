# 캐릭터 5종 검토 패키지

현재 단계는 **전체 사용자 승인을 마친 출시 대기 자산 패키지**다. [승인 파일 목록](FINAL_ASSETS.md)에 후속 앱 연결 대상을 정리했다. 사용자 요청에 따라 목도리를 착용한 새 쿼카 18프레임과 물건별 충돌음까지 먼저 제작했다. 앱·상품 연결 코드는 이번 범위에 포함하지 않는다. 시바·오리·똥·떡볶이는 원작 외형 유지가 승인됐으며 발목 단절과 잘못된 동작은 수정한다. 쿼카는 동물 정체성만 유지해 새로 해석한다. 선택 물건은 테니스공·목욕탕 고무 오리·휴지 뭉치·어묵꼬치·잎사귀다. 물방울과 풀 뭉치는 채택하지 않는다. 현재 작업은 [PR #93](https://github.com/sidey-app/SIDEY-source/pull/93)에 보존하며 최종 검증·필수 CI 이후 main에 병합한다.

캐릭터 5종·물건 5종의 외형/동작과 설명 10개는 승인되었다. 테니스공·어묵꼬치는 소리 1, 오리는 기존 소리로 확정했다. 휴지 소리 2·잎사귀 소리 1과 해당 합성까지 최종 승인되었다. idle은 미리보기 기본값인 기존 0.55/0.55초를 유지한다.

## 로컬 검토

```sh
python3 docs/reviews/character-five/verify_package.py
python3 docs/reviews/character-five/test_verify_package.py
python3 docs/reviews/character-five/serve_review.py
```

<http://127.0.0.1:8765/?v=asset-review-final>에서 최신 후보를 확인한다. 캐릭터 카드에서 걷기·기본·졸기·잠·던지기·피격을 고르고, 물건 카드의 소리 버튼을 바로 누른다. 소리를 듣기 위해 캐릭터나 상대를 선택하거나 던질 필요가 없다. 소리는 한 번에 하나씩 재생하며 멈춤·페이지 숨김 시 중단한다. 물건 회전·충돌·고정된 합성 장면도 카드 안에서 비교한다. 원본·90프레임·60프레임·실루엣·배경·가장자리 검사는 접힌 상세 영역에 둔다.

브라우저 검사는 설치된 Playwright에서 `node docs/reviews/character-five/verify_browser.cjs`로 실행한다. `NODE_PATH`, `SIDEY_REVIEW_CHROMIUM`, `SIDEY_REVIEW_URL`을 지정할 수 있다. 결과와 화면은 `SIDEY_REVIEW_OUTPUT`(기본 `/private/tmp/character-five-browser-evidence`)에 기록한다. 실제 Web Audio 디코딩·재생은 검사하지만 물리 스피커 청취나 앱 실행을 검증한 것으로 보고하지 않는다.

## 현재 검토 파일

- 시바·오리·똥·떡볶이: `candidates/character-v2/<캐릭터 ID>/{appearance,base,throw_hit}.png`. 원본 기본 외형을 유지하고 발 연결·던지기 결함을 보정한 72프레임이다.
- 쿼카: `candidates/character-v3/pixel_quokka/{appearance,base,throw_hit}.png`. 작은 눈·파란 목도리·짧은 팔다리로 다시 만든 18프레임이다. v2의 큰 입과 엇갈린 눈 후보는 보관본이다.
- 물건: `candidates/keepsakes-v2/<물건 ID>/sprite.png`. 테니스공·삑삑 오리·휴지 뭉치·어묵꼬치·잎사귀, 총 60프레임이다.
- 테니스공·어묵꼬치 소리: `candidates/audio-v2/<물건 ID>/{1,2,3}.wav`. 실제 팝·젖은 타격 녹음을 편집한 각 3개 후보 중 두 물건 모두 소리 1로 확정했으며, `audio-v2-review.json`에 출처·편집·레벨·SHA-256을 기록한다.
- 삑삑 오리: `candidates/audio-v2/rubber_duck/original.wav`. 기존 승인된 꽥 소리와 동일 파일을 재사용한다. 그림도 기존 `throwable_squeaky_duck`와 동일하다. 사용자 요청에 따라 이 물건·기존 소리 재사용은 확정했다.
- 휴지·잎사귀 소리: `candidates/audio-v3/<물건 ID>/{A,B}.wav`에서 얇은 종이·잎 마찰 소리를 비교하고 화면에는 소리 1·2로 표시한다. 현재 청취 대상은 총 11개이며 출시 시에는 물건별 선택된 한 파일만 사용한다.
- 고유 설명: `copy-v1/<캐릭터 ID>.json` 5개에 캐릭터와 물건 설명 총 10개를 담는다. 외형 나열 대신 사용자 요청의 짧은 유머로 수정했으며 사용자의 “나머지 다 ok” 응답으로 현재 문구를 승인했다.

원본 `originals/`, 과거 외형·음원·콘셉트와 `history/`는 보존한다. 현재 `package.json`에서 `archived_sprite`·`audio_archive`로 분류한 과거 후보는 출시 자산으로 선택할 수 없다. `references/impact-baseball.wav`도 기존 음량 비교용이며 새 물건 소리가 아니다.

현재 생성기 `build_character_repairs.py`, `build_quokka_v3.py`, `build_keepsakes.py`, `build_audio_v2.py`, `build_audio_v3.py`는 기본 실행 시 읽기 전용 재현 검사를 수행한다. `--write`로 다시 제작해 승인된 파일이 바뀌면 해당 승인을 새로 받아야 한다. 이전 생성기도 과거 후보 재현용으로 보존한다.

## 원본·기여 기록

- 원작 기여: **정지유 (@jungjiyu)**, Git Author `jiyu.jung <libraryofjiyu@gmail.com>`.
- 원본 [PR #27](https://github.com/sidey-app/SIDEY-source/pull/27), 고정 HEAD `ec8dc51cbc0c3eb665c0bca76e2dd7d8ec42fb27`.
- 실제 자산 작성 커밋: `f5f5e63cff7b348ab86433af9b4d72c26f05513f`, AuthorDate `2026-09-03T17:23:45Z`.
- 원본 공동 작성자: `Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- 이관 커밋은 원작자의 PNG 10개만 포함하며 위 작성자·작성일·공동 작성자를 보존한다. 도구·생성 콘셉트·후속 픽셀 수정은 이관 커밋과 분리한다.
- 원본 파일과 SHA-256은 `package.json`; 개별 90프레임 RGBA 해시와 결함은 `source-audit.json`에서 확인한다. 원본 PNG는 PR HEAD 및 최초 자산 커밋 양쪽과 byte 단위로 일치한다.
- 서면 계약: **완료 — 사용자 제공 계획의 확인에 근거함**. 계약 원문·정산 정보는 저장하지 않는다.
- 자산 이용 조건은 [패키지 라이선스 적용 범위](LICENSE.md)와 [SIDEY Paid Asset License 1.0](../../../assets/PAID_ASSET_LICENSE.md)을 따른다. 공개 열람이 다른 제품의 사용·수정·판매 허가를 뜻하지 않는다.

원본 PR의 다른 25종, 하트 쿠션·아메리카노, 앱·상품·마이그레이션·배포 사본은 이관하지 않는다. 기존 main의 활성 자산과 상품은 유지한다. `docs/` 경로는 현재 Pages push 경로 필터에 해당하지 않는다.

## 확인한 결함

- 90프레임 모두 24×24, RGBA·sRGB·hard alpha, 최하단 불투명 행 y=20(하단 3px 여백).
- 5종의 기본 시트 1·3·5 및 동작 시트 6: y=19 전체가 비어 발 6px가 분리됨. 총 20프레임.
- 시바 throw 2=3, 떡볶이 throw 0=1 중복. 상태 간 정상 자세 재사용은 자동 제거하지 않는다.
- 셀 경계 접촉 22프레임. 실제 잘림 여부는 시각 검토가 필요하다.

## 승인·병합 순서

1. 사용자 요청으로 기본 자세·전체 90프레임·물건 60프레임·물건별 음원·합성 후보를 모두 먼저 제작한다. 외형·전체 프레임·움직임·idle 타이밍 승인은 각각 기록한다.
2. 선택된 물건 5종의 그림·회전·충돌 승인, 물건별 번호 음원 선택(기존 삑삑 오리 소리 재사용은 확정), 합성 장면 최종 승인과 캐릭터·물건 고유 설명 10개를 승인한다. 제작을 먼저 허용한 응답은 최종 승인으로 간주하지 않는다.
3. `approvals.json`에 후보 ID·대상 경로·SHA-256·실제 사용자 선택과 근거를 기록한다. 미응답은 pending이다. 파일이 바뀌면 이전 승인은 유효하지 않다. 생성 콘셉트 승인만으로 최종 프레임 승인을 채우지 않는다.
4. `python3 docs/reviews/character-five/verify_package.py --require-approved`가 모든 최종 산출물·승인·해시를 확인해야 병합할 수 있다. 현재는 모든 승인이 완료되어 통과해야 한다.
5. 독립 최종 diff 검토와 정확한 head의 필수 CI 이후 `scripts/skills/workflow.py check/finish`로 후속 PR을 merge commit으로 병합하고 기본 main 작업 폴더를 갱신한다.
6. 병합 뒤 #27에 5종 채택 결과와 후속 PR 링크를 댓글로 남겨 종료한다. 원본 브랜치 force push·삭제는 하지 않는다.
7. main에 비어 있지 않은 원작자 이관 커밋이 포함되는지, GitHub commit author가 `jungjiyu`인지 확인한다. [GitHub 기여자 안내](https://docs.github.com/en/repositories/viewing-activity-and-data-for-your-repository/viewing-a-projects-contributors)에 따라 계정 이메일 연결과 기본 브랜치 반영을 확인하고 집계 화면 갱신은 별도로 기록한다.

앱·상점·서버 연결, 플랫폼 배포 사본, 버전 변경·태그·릴리스·스토어 업로드는 이후 **macOS 심사 완료 및 업데이트 작업 지시**가 있을 때 진행한다. 후속 구현 계약은 [HANDOFF.md](HANDOFF.md)에 둔다.
