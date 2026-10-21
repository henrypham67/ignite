return {
  -- Schema validation for common YAML files
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        yamlls = {
          settings = {
            yaml = {
              schemas = {
                ["https://json.schemastore.org/github-workflow.json"] = ".github/workflows/*.yml",
                ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "docker-compose*.yml",
                ["https://json.schemastore.org/hugo.json"] = "hugo.toml",
              },
            },
          },
        },
      },
    },
  },
}
