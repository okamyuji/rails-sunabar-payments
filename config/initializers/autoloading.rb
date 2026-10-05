# app/handlers 配下は Handlers 名前空間で定義しているので、そのディレクトリの根を Handlers にする。
module Handlers
end

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/handlers"),
  namespace: Handlers
)
