# Load Libraries
library(ragnar)
library(ellmer)
library(fs)
library(tidyverse)
library(glue)
library(blastula)
library(RDCOMClient)

store_location <- "pdf.ragnar.duckdb"
store <- ragnar_store_create(
  store_location,
  embed = \(x) embed_ollama(x, model = "nomic-embed-text:latest"),
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
  You will provide the following for every document passed to you:
    1. Title of Policy
    2. At least three (3) bullet points
    3. A table of information
    4. Summary of the policy
Be concise."
)

client <- chat_ollama(model = "qwen3:0.6b", system_prompt = system_prompt, params = list(temperature = 0.1))

ragnar_register_tool_retrieve(
  chat = client, 
  store = store
)

res <- client$chat("Please summarize the Authorization policy.", echo = "none")
print(res)
