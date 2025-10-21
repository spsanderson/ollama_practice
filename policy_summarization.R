library(ragnar)
library(ellmer)

store_location <- "quarto.ragnar.duckdb"
store <- ragnar_store_create(
  store_location,
  embed = \(x) embed_ollama(x, model = "embeddinggemma"),
  overwrite = TRUE
)

anthem_files_path <- "W:/PATACCT/BusinessOfc/Revenue Cycle Analyst/Payer_Policies/Anthem_PDFs/"
anthem_files <- list.files(anthem_files_path, full.names = TRUE)
anthem_files_subset <- anthem_files[2]
anthem_files_subset

for (file in anthem_files_subset) {
  chunks <- file |>
    read_as_markdown() |>
    markdown_chunk()

  ragnar_store_insert(store, chunks)
}

ragnar_store_build_index(store)

system_prompt <- stringr::str_squish(
  "You are an expert assistant in document summarization.
  When responding, you first quote relevant material from the documents in the store,
  provide links to the sources, and then add your own context and interpretation.
  You will provide at least three (3) bullet points and a table of information
  for every document you review. Be concise."
)

client <- chat_ollama(model = "llama3.2", system_prompt = system_prompt)

ragnar_register_tool_retrieve(
  chat = client, 
  store = store,
  top_k = 10,
  description = "Anthem Policy",
)

res <- client$chat("Please summarize the Authorization policy.")
