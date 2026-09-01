import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/futhr/letterpress",
    version_tag_prefix: "v",
    version_source: :mix,
    manage_mix_version?: true,
    managed_files: [
      {"npm/language/package.json", :json},
      {"npm/svelte/package.json", :json}
    ]
end
