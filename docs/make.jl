using Documenter
using Xitip

DocMeta.setdocmeta!(Xitip, :DocTestSetup, :(using Xitip); recursive=true)

makedocs(;
    modules = [Xitip],
    authors = "Rethna Pulikkoonattu, Etienne Perron, Suhas Diggavi and contributors",
    sitename = "Xitip.jl",
    format = Documenter.HTML(;
        canonical = "https://geekymode.github.io/Xitip.jl",
        edit_link = "main",
        prettyurls = get(ENV, "CI", "false") == "true",
    ),
    pages = [
        "Home" => "index.md",
        "Xitip foundations" => "foundations.md",
        "Expression syntax" => "syntax.md",
        "Proofs and counterexamples" => "proofs.md",
        "Examples" => "examples.md",
        "Illustrations" => "illustrations.md",
        "Command line" => "cli.md",
        "How it works" => "internals.md",
        "API reference" => "api.md",
    ],
    checkdocs = :exports,
)

deploydocs(;
    repo = "github.com/geekymode/Xitip.jl",
    devbranch = "main",
)
