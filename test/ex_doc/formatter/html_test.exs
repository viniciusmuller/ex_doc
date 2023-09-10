defmodule ExDoc.Formatter.HTMLTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  alias ExDoc.Formatter.HTML

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    output = tmp_dir <> "/html"
    File.mkdir_p!(output)
    File.touch!(output <> "/.ex_doc")
  end

  defp read_wildcard!(path) do
    [file] = Path.wildcard(path)
    File.read!(file)
  end

  @before_closing_head_tag_content_html "UNIQUE:<dont-escape>&copy;BEFORE-CLOSING-HEAD-TAG-EPUB</dont-escape>"
  @before_closing_body_tag_content_html "UNIQUE:<dont-escape>&copy;BEFORE-CLOSING-BODY-TAG-EPUB</dont-escape>"

  defp before_closing_head_tag(:html), do: @before_closing_head_tag_content_html
  defp before_closing_body_tag(:html), do: @before_closing_body_tag_content_html

  def before_closing_head_tag(:html, name), do: "<meta name=#{name}>"
  def before_closing_body_tag(:html, name), do: "<p>#{name}</p>"

  defp doc_config(%{tmp_dir: tmp_dir} = _context) do
    [
      apps: [:elixir],
      project: "Elixir",
      version: "1.0.1",
      formatter: "html",
      assets: "test/tmp/html_assets",
      output: tmp_dir <> "/html",
      source_beam: "test/tmp/beam",
      source_url: "https://github.com/elixir-lang/elixir",
      logo: "test/fixtures/elixir.png",
      extras: []
    ]
  end

  defp doc_config(context, config) when is_map(context) and is_list(config) do
    Keyword.merge(doc_config(context), config)
  end

  defp generate_docs(config) do
    config = Keyword.put_new(config, :skip_undefined_reference_warnings_on, ["Warnings"])
    ExDoc.generate_docs(config[:project], config[:version], config)
  end

  test "normalizes options", %{tmp_dir: tmp_dir} = context do
    # 1. Check for output dir having trailing "/" stripped
    # 2. Check for default [main: "api-reference"]
    generate_docs(doc_config(context, output: tmp_dir <> "/html//", main: nil))

    content = File.read!(tmp_dir <> "/html/index.html")
    assert content =~ ~r{<meta http-equiv="refresh" content="0; url=api-reference.html">}
    assert File.regular?(tmp_dir <> "/html/api-reference.html")

    # 3. main as index is not allowed
    config = doc_config(context, main: "index")

    assert_raise ArgumentError,
                 ~S("main" cannot be set to "index", otherwise it will recursively link to itself),
                 fn -> generate_docs(config) end
  end

  describe "strip_tags" do
    test "removes html tags from text leaving the content" do
      assert HTML.strip_tags("<em>Hello</em> World!<br/>") == "Hello World!"
      assert HTML.strip_tags("Go <a href=\"#top\" class='small' disabled>back</a>") == "Go back"
      assert HTML.strip_tags("Git opts (<code class=\"inline\">:git</code>)") == "Git opts (:git)"
      assert HTML.strip_tags("<p>P1.</p><p>P2</p>") == "P1.P2"
      assert HTML.strip_tags("<p>P1.</p><p>P2</p>", " ") == " P1.  P2 "
    end
  end

  describe "text_to_id" do
    test "id generation" do
      assert HTML.text_to_id("“Stale”") == "stale"
      assert HTML.text_to_id("José") == "josé"
      assert HTML.text_to_id(" a - b ") == "a-b"
      assert HTML.text_to_id(" ☃ ") == ""
      assert HTML.text_to_id(" &sup2; ") == ""
      assert HTML.text_to_id(" &#9180; ") == ""
      assert HTML.text_to_id("Git opts (<code class=\"inline\">:git</code>)") == "git-opts-git"
    end
  end

  test "multiple extras with the same name", c do
    File.mkdir_p!("#{c.tmp_dir}/foo")

    File.write!("#{c.tmp_dir}/foo/README.md", """
    # README foo
    """)

    File.mkdir_p!("#{c.tmp_dir}/bar")

    File.write!("#{c.tmp_dir}/bar/README.md", """
    # README bar
    """)

    config =
      Keyword.replace!(doc_config(c), :extras, [
        "#{c.tmp_dir}/foo/README.md",
        "#{c.tmp_dir}/bar/README.md"
      ])

    generate_docs(config)

    foo_content = EasyHTML.parse!(File.read!("#{c.tmp_dir}/html/readme-1.html"))["#content"]
    bar_content = EasyHTML.parse!(File.read!("#{c.tmp_dir}/html/readme-2.html"))["#content"]

    assert to_string(foo_content["h1 > span"]) == "README foo"
    assert to_string(bar_content["h1 > span"]) == "README bar"
  end

  test "warns when generating an index.html file with an invalid redirect",
       %{tmp_dir: tmp_dir} = context do
    output =
      capture_io(:stderr, fn ->
        generate_docs(doc_config(context, main: "Randomerror"))
      end)

    assert output =~ "warning: index.html redirects to Randomerror.html, which does not exist\n"
    assert File.regular?(tmp_dir <> "/html/index.html")
    assert File.regular?(tmp_dir <> "/html/RandomError.html")
  end

  test "warns on undefined functions", context do
    output =
      capture_io(:stderr, fn ->
        generate_docs(doc_config(context, skip_undefined_reference_warnings_on: []))
      end)

    assert output =~ ~r"Warnings.bar/0.*\n  test/fixtures/warnings.ex:2: Warnings"
    assert output =~ ~r"Warnings.bar/0.*\n  test/fixtures/warnings.ex:18: Warnings.foo/0"
    assert output =~ ~r"Warnings.bar/0.*\n  test/fixtures/warnings.ex:13: c:Warnings.handle_foo/0"
    assert output =~ ~r"Warnings.bar/0.*\n  test/fixtures/warnings.ex:8: t:Warnings.t/0"
  end

  test "warns when referencing typespec on filtered module", context do
    output =
      capture_io(:stderr, fn ->
        generate_docs(doc_config(context, filter_modules: ~r/ReferencesTypespec/))
      end)

    assert output =~ "typespec references filtered module: TypesAndSpecs.public(integer())"
  end

  test "generates headers for index.html and module pages", %{tmp_dir: tmp_dir} = context do
    generate_docs(doc_config(context, main: "RandomError"))
    content_index = File.read!(tmp_dir <> "/html/index.html")
    content_module = File.read!(tmp_dir <> "/html/RandomError.html")

    # Regular Expressions
    re = %{
      shared: %{
        charset: ~r{<meta charset="utf-8">},
        generator: ~r{<meta name="generator" content="ExDoc v#{ExDoc.version()}">}
      },
      index: %{
        title: ~r{<title>Elixir v1.0.1 — Documentation</title>},
        refresh: ~r{<meta http-equiv="refresh" content="0; url=RandomError.html">}
      },
      module: %{
        title: ~r{<title>RandomError — Elixir v1.0.1</title>},
        viewport: ~r{<meta name="viewport" content="width=device-width, initial-scale=1.0">},
        x_ua: ~r{<meta http-equiv="x-ua-compatible" content="ie=edge">}
      }
    }

    assert content_index =~ re[:shared][:charset]
    assert content_index =~ re[:shared][:generator]
    assert content_index =~ re[:index][:title]
    assert content_index =~ re[:index][:refresh]
    refute content_index =~ re[:module][:title]
    refute content_index =~ re[:module][:viewport]
    refute content_index =~ re[:module][:x_ua]

    assert content_module =~ re[:shared][:charset]
    assert content_module =~ re[:shared][:generator]
    assert content_module =~ re[:module][:title]
    assert content_module =~ re[:module][:viewport]
    assert content_module =~ re[:module][:x_ua]
    refute content_module =~ re[:index][:title]
    refute content_module =~ re[:index][:refresh]
  end

  test "allows to set the authors of the document", %{tmp_dir: tmp_dir} = context do
    generate_docs(doc_config(context, authors: ["John Doe", "Jane Doe"]))
    content_index = File.read!(tmp_dir <> "/html/api-reference.html")

    assert content_index =~ ~r{<meta name="author" content="John Doe, Jane Doe">}
  end

  test "generates in default directory with redirect index.html file",
       %{tmp_dir: tmp_dir} = context do
    generate_docs(doc_config(context))

    assert File.regular?(tmp_dir <> "/html/CompiledWithDocs.html")
    assert File.regular?(tmp_dir <> "/html/CompiledWithDocs.Nested.html")

    assert [_] = Path.wildcard(tmp_dir <> "/html/dist/html-*.js")
    assert [_] = Path.wildcard(tmp_dir <> "/html/dist/html-elixir-*.css")

    content = File.read!(tmp_dir <> "/html/index.html")
    assert content =~ ~r{<meta http-equiv="refresh" content="0; url=api-reference.html">}
  end

  test "generates all listing files", %{tmp_dir: tmp_dir} = context do
    generate_docs(doc_config(context))
    "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

    assert %{
             "modules" => [
               %{"id" => "CallbacksNoDocs"},
               %{"id" => "Common.Nesting.Prefix.B.A"},
               %{"id" => "Common.Nesting.Prefix.B.B.A"},
               %{"id" => "Common.Nesting.Prefix.B.C"},
               %{"id" => "Common.Nesting.Prefix.C"},
               %{"id" => "CompiledWithDocs"},
               %{"id" => "CompiledWithDocs.Nested"},
               %{"id" => "CompiledWithoutDocs"},
               %{"id" => "CustomBehaviourImpl"},
               %{"id" => "CustomBehaviourOne"},
               %{"id" => "CustomBehaviourTwo"},
               %{"id" => "CustomProtocol"},
               %{"id" => "DuplicateHeadings"},
               %{"id" => "OverlappingDefaults"},
               %{"id" => "ReferencesTypespec"},
               %{"id" => "TypesAndSpecs"},
               %{"id" => "TypesAndSpecs.Sub"},
               %{"id" => "Warnings"},
               %{"id" => "RandomError"}
             ],
             "tasks" => [
               %{"id" => "Mix.Tasks.TaskWithDocs", "title" => "mix task_with_docs"}
             ]
           } = Jason.decode!(content)
  end

  test "generates the api reference file", %{tmp_dir: tmp_dir} = context do
    generate_docs(doc_config(context))

    content = File.read!(tmp_dir <> "/html/api-reference.html")

    assert content =~ ~r{<a href="https://github.com/elixir-lang/elixir" title="View Source"}
    assert content =~ ~r{<a href="CompiledWithDocs.html" translate="no">CompiledWithDocs</a>}
    assert content =~ ~r{<p>moduledoc</p>}

    assert content =~
             ~r{<a href="CompiledWithDocs.Nested.html" translate="no">CompiledWithDocs.Nested</a>}

    assert content =~
             ~r{<a href="Mix.Tasks.TaskWithDocs.html" translate="no">mix task_with_docs</a>}
  end

  test "groups modules by nesting", %{tmp_dir: tmp_dir} = context do
    doc_config(context)
    |> Keyword.put(:nest_modules_by_prefix, [Common.Nesting.Prefix.B, Common.Nesting.Prefix.B.B])
    |> generate_docs()

    "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")
    assert {:ok, %{"modules" => modules}} = Jason.decode(content)

    assert %{"nested_context" => "Common.Nesting.Prefix.B"} =
             Enum.find(modules, fn %{"id" => id} -> id == "Common.Nesting.Prefix.B.C" end)

    assert %{"nested_context" => "Common.Nesting.Prefix.B.B"} =
             Enum.find(modules, fn %{"id" => id} -> id == "Common.Nesting.Prefix.B.B.A" end)
  end

  test "groups modules by nesting respecting groups", %{tmp_dir: tmp_dir} = context do
    groups = [
      Group1: [
        Common.Nesting.Prefix.B.A,
        Common.Nesting.Prefix.B.C
      ],
      Group2: [
        Common.Nesting.Prefix.B.B.A,
        Common.Nesting.Prefix.C
      ]
    ]

    doc_config(context)
    |> Keyword.put(:nest_modules_by_prefix, [Common.Nesting.Prefix.B, Common.Nesting.Prefix.B.B])
    |> Keyword.put(:groups_for_modules, groups)
    |> generate_docs()

    "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")
    assert {:ok, %{"modules" => modules}} = Jason.decode(content)

    assert %{"Group1" => [_, _], "Group2" => [_, _]} =
             Enum.group_by(modules, &Map.get(&1, "group"))
  end

  describe "generates logo" do
    test "overriding previous entries", %{tmp_dir: tmp_dir} = context do
      File.mkdir_p!(tmp_dir <> "/html/assets")
      File.touch!(tmp_dir <> "/html/assets/logo.png")
      generate_docs(doc_config(context, logo: "test/fixtures/elixir.png"))
      assert File.read!(tmp_dir <> "/html/assets/logo.png") != ""
    end

    test "fails when logo is not an allowed format", context do
      config = doc_config(context, logo: "README.md")

      assert_raise ArgumentError,
                   "image format not recognized, allowed formats are: .jpg, .png",
                   fn -> generate_docs(config) end
    end
  end

  describe "canonical URL" do
    test "is included when canonical options is specified", %{tmp_dir: tmp_dir} = context do
      config =
        doc_config(context,
          extras: ["test/fixtures/README.md"],
          canonical: "https://hexdocs.pm/elixir/"
        )

      generate_docs(config)
      content = File.read!(tmp_dir <> "/html/api-reference.html")
      assert content =~ ~r{<link rel="canonical" href="https://hexdocs.pm/elixir/}

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~r{<link rel="canonical" href="https://hexdocs.pm/elixir/}
    end

    test "is not included when canonical is nil", %{tmp_dir: tmp_dir} = context do
      config = doc_config(context, canonical: nil)
      generate_docs(config)
      content = File.read!(tmp_dir <> "/html/api-reference.html")
      refute content =~ ~r{<link rel="canonical" href="}
    end
  end

  describe "generates extras" do
    @extras [
      "test/fixtures/LICENSE",
      "test/fixtures/PlainText.txt",
      "test/fixtures/PlainTextFiles.md",
      "test/fixtures/README.md",
      "test/fixtures/LivebookFile.livemd",
      "test/fixtures/cheatsheets.cheatmd"
    ]

    test "includes source `.livemd` files", %{tmp_dir: tmp_dir} = context do
      generate_docs(doc_config(context, extras: @extras))

      refute File.exists?(tmp_dir <> "/html/LICENSE")
      refute File.exists?(tmp_dir <> "/html/license")
      refute File.exists?(tmp_dir <> "/html/PlainText.txt")
      refute File.exists?(tmp_dir <> "/html/plaintext.txt")
      refute File.exists?(tmp_dir <> "/html/PlainTextFiles.md")
      refute File.exists?(tmp_dir <> "/html/plaintextfiles.md")
      refute File.exists?(tmp_dir <> "/html/README.md")
      refute File.exists?(tmp_dir <> "/html/readme.md")

      assert File.read!("test/fixtures/LivebookFile.livemd") ==
               File.read!(tmp_dir <> "/html/livebookfile.livemd")
    end

    test "alongside other content", %{tmp_dir: tmp_dir} = context do
      config = doc_config(context, main: "readme", extras: @extras)
      generate_docs(config)

      content = File.read!(tmp_dir <> "/html/index.html")
      assert content =~ ~r{<meta http-equiv="refresh" content="0; url=readme.html">}

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~r{<title>README [^<]*</title>}

      assert content =~
               ~r{<h2 id="header-sample" class="section-heading">.*<a href="#header-sample">.*<i class="ri-link-m" aria-hidden="true"></i>.*<code(\sclass="inline")?>Header</code> sample.*</a>.*</h2>}ms

      assert content =~
               ~r{<h2 id="more-than" class="section-heading">.*<a href="#more-than">.*<i class="ri-link-m" aria-hidden="true"></i>.*more &gt; than.*</a>.*</h2>}ms

      assert content =~ ~r{<a href="RandomError.html"><code(\sclass="inline")?>RandomError</code>}

      assert content =~
               ~r{<a href="CustomBehaviourImpl.html#hello/1"><code(\sclass="inline")?>CustomBehaviourImpl.hello/1</code>}

      assert content =~
               ~r{<a href="TypesAndSpecs.Sub.html"><code(\sclass="inline")?>TypesAndSpecs.Sub</code></a>}

      assert content =~
               ~r{<a href="TypesAndSpecs.Sub.html"><code(\sclass="inline")?>TypesAndSpecs.Sub</code></a>}

      assert content =~
               ~r{<a href="typespecs.html#basic-types"><code(\sclass="inline")?>atom/0</code></a>}

      assert content =~
               ~r{<a href="https://hexdocs.pm/mix/Mix.Tasks.Compile.Elixir.html"><code(\sclass="inline")?>mix compile.elixir</code></a>}

      refute content =~
               ~R{<img src="https://livebook.dev/badge/v1/blue.svg" alt="Run in Livebook" width="150" />}

      assert content =~ "<p><strong>raw content</strong></p>"

      assert content =~
               ~s{<a href="https://github.com/elixir-lang/elixir/blob/main/test/fixtures/README.md#L1" title="View Source"}

      content = File.read!(tmp_dir <> "/html/plaintextfiles.html")

      assert content =~ ~r{Plain Text Files</span>.*</h1>}s

      assert content =~
               ~R{<p>Read the <a href="license.html">license</a> and the <a href="plaintext.html">plain-text file</a>.}

      plain_text_file = File.read!(tmp_dir <> "/html/plaintext.html")

      assert plain_text_file =~ ~r{PlainText</span>.*</h1>}s

      assert plain_text_file =~
               ~R{<pre>\nThis is plain\n  text and nothing\n.+\s+good bye\n</pre>}s

      assert plain_text_file =~ ~s{\n## Neither formatted\n}
      assert plain_text_file =~ ~s{\n      `t:term/0`\n}

      license = File.read!(tmp_dir <> "/html/license.html")

      assert license =~ ~r{LICENSE</span>.*</h1>}s

      assert license =~
               ~s{<pre>\nLicensed under the Apache License, Version 2.0 (the &quot;License&quot;)}

      content = File.read!(tmp_dir <> "/html/livebookfile.html")

      assert content =~ ~r{<span>Title for Livebook Files</span>\s*</h1>}

      assert content =~
               ~s{<a href="https://github.com/elixir-lang/elixir/blob/main/test/fixtures/LivebookFile.livemd#L1" title="View Source"}

      assert content =~
               ~s{<p>Read <code class="inline">.livemd</code> files generated by <a href="https://github.com/livebook-dev/livebook">livebook</a>.}

      assert content =~
               ~s{<img src="https://livebook.dev/badge/v1/blue.svg" alt="Run in Livebook" width="150" />}

      content = File.read!(tmp_dir <> "/html/cheatsheets.html")

      assert content =~ ~s{<section class="h2"><h2 id="getting-started" class="section-heading">}
      assert content =~ ~s{<section class="h3"><h3 id="hello-world" class="section-heading">}
      assert content =~ ~s{<section class="h2"><h2 id="types" class="section-heading">}
      assert content =~ ~s{<section class="h3"><h3 id="operators" class="section-heading">}
    end

    test "with absolute and dot-relative paths for extra", %{tmp_dir: tmp_dir} = context do
      config =
        doc_config(context,
          extras: ["./test/fixtures/README.md", Path.expand("test/fixtures/LivebookFile.livemd")]
        )

      generate_docs(config)

      content = File.read!(tmp_dir <> "/html/readme.html")

      assert content =~
               ~s{<a href="https://github.com/elixir-lang/elixir/blob/main/test/fixtures/README.md#L1" title="View Source"}

      content = File.read!(tmp_dir <> "/html/livebookfile.html")

      assert content =~
               ~s{<a href="https://github.com/elixir-lang/elixir/blob/main/test/fixtures/LivebookFile.livemd#L1" title="View Source"}
    end

    test "with html comments", %{tmp_dir: tmp_dir} = context do
      generate_docs(
        doc_config(context, source_beam: "unknown", extras: ["test/fixtures/README.md"])
      )

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~s(<!-- HTML comment -->)
    end

    test "without any other content", %{tmp_dir: tmp_dir} = context do
      generate_docs(doc_config(context, source_beam: "unknown", extras: @extras))
      "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

      assert [
               %{"id" => "api-reference"},
               %{"id" => "license"},
               %{"id" => "plaintext"},
               %{"id" => "plaintextfiles"},
               %{
                 "id" => "readme",
                 "headers" => [
                   %{"anchor" => "heading-without-content", "id" => "Heading without content"},
                   %{"anchor" => "header-sample", "id" => "Header sample"},
                   %{"anchor" => "more-than", "id" => "more &gt; than"}
                 ]
               },
               %{"id" => "livebookfile"},
               %{"id" => "cheatsheets"}
             ] = Jason.decode!(content)["extras"]
    end

    test "containing settext headers while discarding links on header",
         %{tmp_dir: tmp_dir} = context do
      generate_docs(
        doc_config(context,
          source_beam: "unknown",
          extras: ["test/fixtures/ExtraPageWithSettextHeader.md"]
        )
      )

      "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

      assert [
               %{"id" => "api-reference"},
               %{
                 "id" => "extrapagewithsettextheader",
                 "title" => "Extra Page Title",
                 "headers" => [
                   %{"anchor" => "section-one", "id" => "Section One"},
                   %{"anchor" => "section-two", "id" => "Section Two"}
                 ]
               }
             ] = Jason.decode!(content)["extras"]
    end

    test "with custom names", %{tmp_dir: tmp_dir} = context do
      generate_docs(
        doc_config(context,
          extras: [
            "test/fixtures/PlainTextFiles.md",
            "test/fixtures/LICENSE": [filename: "linked-license"],
            "test/fixtures/PlainText.txt": [filename: "plain_text"]
          ]
        )
      )

      refute File.regular?(tmp_dir <> "/html/license.html")
      assert File.regular?(tmp_dir <> "/html/linked-license.html")

      refute File.regular?(tmp_dir <> "/html/plaintext.html")
      assert File.regular?(tmp_dir <> "/html/plain_text.html")

      content = File.read!(tmp_dir <> "/html/plaintextfiles.html")

      assert content =~ ~r{Plain Text Files</span>.*</h1>}s

      assert content =~
               ~R{<p>Read the <a href="linked-license.html">license</a> and the <a href="plain_text.html">plain-text file</a>.}

      "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

      assert [
               %{"id" => "api-reference"},
               %{"id" => "plaintextfiles"},
               %{"id" => "linked-license", "title" => "LICENSE"},
               %{"id" => "plain_text"}
             ] = Jason.decode!(content)["extras"]
    end

    test "with custom title", %{tmp_dir: tmp_dir} = context do
      generate_docs(
        doc_config(context, extras: ["test/fixtures/README.md": [title: "Getting Started"]])
      )

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~r{<title>Getting Started — Elixir v1.0.1</title>}
      "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

      assert [
               %{"headers" => [%{"id" => "Modules"}, %{"id" => "Mix Tasks"}]},
               %{
                 "headers" => [
                   %{"anchor" => "heading-without-content", "id" => "Heading without content"},
                   %{"anchor" => "header-sample", "id" => "Header sample"},
                   %{"anchor" => "more-than", "id" => "more &gt; than"}
                 ]
               }
             ] = Jason.decode!(content)["extras"]
    end

    test "with custom groups", %{tmp_dir: tmp_dir} = context do
      extra_config = [
        extras: ["test/fixtures/README.md"],
        groups_for_extras: [Intro: ~r/fixtures\/READ.?/]
      ]

      generate_docs(doc_config(context, extra_config))
      "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

      assert [
               %{"group" => ""},
               %{"group" => "Intro", "id" => "readme", "title" => "README"}
             ] = Jason.decode!(content)["extras"]
    end

    test "with auto-extracted titles", %{tmp_dir: tmp_dir} = context do
      generate_docs(doc_config(context, extras: ["test/fixtures/ExtraPage.md"]))
      content = File.read!(tmp_dir <> "/html/extrapage.html")
      assert content =~ ~r{<title>Extra Page Title — Elixir v1.0.1</title>}
      "sidebarNodes=" <> content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")

      assert [
               %{"id" => "api-reference"},
               %{"id" => "extrapage"}
             ] = Jason.decode!(content)["extras"]
    end

    test "without api-reference", %{tmp_dir: tmp_dir} = context do
      generate_docs(
        doc_config(context,
          api_reference: false,
          extras: ["test/fixtures/README.md"],
          main: "readme"
        )
      )

      refute File.exists?(tmp_dir <> "/html/api-reference.html")
      content = read_wildcard!(tmp_dir <> "/html/dist/sidebar_items-*.js")
      refute content =~ ~r{"id":"api-reference","title":"API Reference"}
    end

    test "pages include links to the previous/next page if applicable",
         %{tmp_dir: tmp_dir} = context do
      generate_docs(
        doc_config(context,
          extras: [
            "test/fixtures/LICENSE",
            "test/fixtures/README.md"
          ]
        )
      )

      # We have three extras: API Reference, LICENSE and README

      content_first = File.read!(tmp_dir <> "/html/api-reference.html")

      refute content_first =~ ~r{Previous Page}

      assert content_first =~
               ~r{<a href="license.html" class="bottom-actions-button" rel="next">\s*<span class="subheader">\s*Next Page →\s*</span>\s*<span class="title">\s*LICENSE\s*</span>\s*</a>}

      content_middle = File.read!(tmp_dir <> "/html/license.html")

      assert content_middle =~
               ~r{<a href="api-reference.html" class="bottom-actions-button" rel="prev">\s*<span class="subheader">\s*← Previous Page\s*</span>\s*<span class="title">\s*API Reference\s*</span>\s*</a>}

      assert content_middle =~
               ~r{<a href="readme.html" class="bottom-actions-button" rel="next">\s*<span class="subheader">\s*Next Page →\s*</span>\s*<span class="title">\s*README\s*</span>\s*</a>}

      content_last = File.read!(tmp_dir <> "/html/readme.html")

      assert content_last =~
               ~r{<a href="license.html" class="bottom-actions-button" rel="prev">\s*<span class="subheader">\s*← Previous Page\s*</span>\s*<span class="title">\s*LICENSE\s*</span>\s*</a>}

      refute content_last =~ ~r{Next Page}
    end

    test "before_closing_*_tags required by the user are placed in the right place using a map",
         %{
           tmp_dir: tmp_dir
         } = context do
      generate_docs(
        doc_config(context,
          before_closing_head_tag: %{html: "<meta name=StaticDemo>"},
          before_closing_body_tag: %{html: "<p>StaticDemo</p>"},
          extras: ["test/fixtures/README.md"]
        )
      )

      content = File.read!(tmp_dir <> "/html/api-reference.html")
      assert content =~ ~r[<meta name=StaticDemo>\s*</head>]
      assert content =~ ~r[<p>StaticDemo</p>\s*</body>]

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~r[<meta name=StaticDemo>\s*</head>]
      assert content =~ ~r[<p>StaticDemo</p>\s*</body>]
    end

    test "before_closing_*_tags required by the user are placed in the right place using MFA",
         %{
           tmp_dir: tmp_dir
         } = context do
      generate_docs(
        doc_config(context,
          before_closing_head_tag: {__MODULE__, :before_closing_head_tag, ["Demo"]},
          before_closing_body_tag: {__MODULE__, :before_closing_body_tag, ["Demo"]},
          extras: ["test/fixtures/README.md"]
        )
      )

      content = File.read!(tmp_dir <> "/html/api-reference.html")
      assert content =~ ~r[<meta name=Demo>\s*</head>]
      assert content =~ ~r[<p>Demo</p>\s*</body>]

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~r[<meta name=Demo>\s*</head>]
      assert content =~ ~r[<p>Demo</p>\s*</body>]
    end

    test "before_closing_*_tags required by the user are placed in the right place",
         %{
           tmp_dir: tmp_dir
         } = context do
      generate_docs(
        doc_config(context,
          before_closing_head_tag: &before_closing_head_tag/1,
          before_closing_body_tag: &before_closing_body_tag/1,
          extras: ["test/fixtures/README.md"]
        )
      )

      content = File.read!(tmp_dir <> "/html/api-reference.html")
      assert content =~ ~r[#{@before_closing_head_tag_content_html}\s*</head>]
      assert content =~ ~r[#{@before_closing_body_tag_content_html}\s*</body>]

      content = File.read!(tmp_dir <> "/html/readme.html")
      assert content =~ ~r[#{@before_closing_head_tag_content_html}\s*</head>]
      assert content =~ ~r[#{@before_closing_body_tag_content_html}\s*</body>]
    end
  end

  describe ".build" do
    test "stores generated content", %{tmp_dir: tmp_dir} = context do
      config =
        doc_config(context, extras: ["test/fixtures/README.md"], logo: "test/fixtures/elixir.png")

      generate_docs(config)

      # Verify necessary files in .build
      content = File.read!(tmp_dir <> "/html/.build")
      assert content =~ ~r(^readme\.html$)m
      assert content =~ ~r(^api-reference\.html$)m
      assert content =~ ~r(^dist/sidebar_items-[\w]{8}\.js$)m
      assert content =~ ~r(^dist/html-[\w]{8}\.js$)m
      assert content =~ ~r(^dist/html-elixir-[\w]{8}\.css$)m
      assert content =~ ~r(^assets/logo\.png$)m
      assert content =~ ~r(^index\.html$)m
      assert content =~ ~r(^404\.html$)m

      # Verify the files listed in .build actually exist
      files =
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&Path.join(tmp_dir <> "/html", &1))

      for file <- files do
        assert File.exists?(file)
      end
    end

    test "does not delete files not listed in .build", %{tmp_dir: tmp_dir} = context do
      keep = tmp_dir <> "/html/keep"
      config = doc_config(context)
      generate_docs(config)
      File.touch!(keep)
      generate_docs(config)
      assert File.exists?(keep)
      content = File.read!(tmp_dir <> "/html/.build")
      refute content =~ ~r{keep}
    end
  end

  test "assets required by the user end up in the right place", %{tmp_dir: tmp_dir} = context do
    File.mkdir_p!("test/tmp/html_assets/hello")
    File.touch!("test/tmp/html_assets/hello/world")

    generate_docs(
      doc_config(context, assets: "test/tmp/html_assets", logo: "test/fixtures/elixir.png")
    )

    assert File.regular?(tmp_dir <> "/html/assets/logo.png")
    assert File.regular?(tmp_dir <> "/html/assets/hello/world")
  after
    File.rm_rf!("test/tmp/html_assets")
  end
end
