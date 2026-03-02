# Terraform 쉘 단축키 (zsh alias)

> 마지막 업데이트: 2026-03-02

---

## 설정 방법

`~/.zshrc` 파일 하단에 추가한다.

```bash
alias tf='terraform'
```

추가 후 적용:
```bash
source ~/.zshrc
```

---

## 현재 단축키

| 단축키 | 원래 명령어 |
|--------|-----------|
| `tf` | `terraform` |

---

## 향후 확장 참고

단축키가 더 필요해지면 아래 패턴으로 추가한다.

**단순 alias** — 명령어 전체를 줄일 때:
```bash
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
```

**함수** — 플래그(`-parallelism` 등)까지 포함하고 싶을 때:
```bash
# alias는 플래그 단위 단축 불가 → 함수로 대체
tfa() {
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    terraform apply -parallelism="$1" "${@:2}"
  else
    terraform apply "$@"
  fi
}
# tfa      → terraform apply
# tfa 20   → terraform apply -parallelism=20
```

---

## 참고

- [Terraform CLI 공식 문서](https://developer.hashicorp.com/terraform/cli)
