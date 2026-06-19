# rails-sunabar-payments

GMOあおぞらネット銀行のsandbox API(sunabar)を利用した決済管理システム。
[go-sunabar-payments](https://github.com/okamyuji/go-sunabar-payments)のRails8.1移植版。

## 技術スタック

- Ruby3.4(YJIT) / Rails8.1
- MySQL8.0
- SolidQueue(Outbox Relay / Reconciler)
- Docker(compose.yml)

## 機能

- 振込依頼・状態管理(Transactional Outboxパターン)
- 入金消込(バーチャル口座 → 請求書突合)
- 通知(イベント駆動、冪等性保証)
- 管理画面(ERB + Tailwind CSS)

## セットアップ

```bash
docker compose up -d db
bundle install
bin/rails db:setup
bin/rails server
```

SolidQueueワーカー:
```bash
bin/rails solid_queue:start
```

## テスト

```bash
bin/rails test          # ユニット/結合(199件)
bin/rails test:system   # E2E(5件)
```

## 品質ゲート

```bash
gitleaks detect --source .
bundle exec stree check app lib
bundle exec rubocop
```

pre-commit(lefthook)で自動実行。

## 設計書

- [要件定義書](docs/01_requirements.md)
- [基本設計書](docs/02_basic_design.md)
- [詳細設計書](docs/03_detailed_design.md)
