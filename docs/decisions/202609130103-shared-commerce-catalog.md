# 공유 commerce catalog

Status: Accepted
Decided: 2026-09-13 01:03 KST
Evidence: [commit b256426](https://github.com/sidey-app/SIDEY-source/commit/b256426f88f34488e251370053e6ba3231964a63)

## Context

상품 metadata가 client, checkout, website와 server 문서에 따로 존재하면서 가격,
식별자와 표시 정보가 어긋날 수 있었다. 사람이 같은 표를 여러 파일에서 고치는 방식은
이 drift를 안정적으로 막지 못했다.

## Decision

`assets/v1/commerce-catalog.json`을 public 상품 metadata의 canonical source로 둔다.
Asset 구조와 platform support는 `assets/v1/manifest.json`이 소유한다. Website와 native
mirror는 generator로 만들고 원본과 일치를 검사한다. Backend는 검토된 public commit의
snapshot과 provenance를 받아 server mapping을 별도로 생성한다.

## Consequences

가격, 상품 ID와 개수는 Markdown 표에 복제하지 않는다. Public catalog 변경이 backend
배포를 자동 수행하지 않으며, 각 platform snapshot은 어떤 reviewed source에서 생성됐는지
추적해야 한다.
