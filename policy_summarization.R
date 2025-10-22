# Load Libraries ----
library(ragnar)
library(ellmer)
library(fs)
library(tidyverse)
library(glue)
library(blastula)
library(RDCOMClient)


# Files ----
anthem_files_path <- "W:/PATACCT/BusinessOfc/Revenue Cycle Analyst/Payer_Policies/Anthem_PDFs/"
anthem_files <- list.files(anthem_files_path, full.names = TRUE)

# System Prompt ----
system_prompt <- str_squish(
  "
  You are an expert assistant that summarizes **Health Insurance Payer Policies** clearly and accurately for healthcare, billing, and administrative users.

  When responding, you should first quote relevant material from the documents in the store,
  provide links to the sources, and then add your own context and interpretation. Try to be as concise
  as you are thorough.

  For every document passed to you the output should if applicable include:

  1. Policy Summary: 1–2 paragraphs describing purpose, scope, and coverage intent.
  2. Key Points: At least 3 concise bullet points summarizing coverage criteria, limitations, exclusions, or authorization requirements.
  3. Policy Information Table

  **Model Behavior Rules:**

  * If information is missing, state “Not specified in document.”
  * Do not infer or assume; summarize only verifiable content.
  * Maintain neutral, factual tone using payer-standard language (e.g., “medically necessary,” “experimental/investigational”).
  * Simplify complex clinical text while preserving accuracy.
  * Always follow the structure: **Policy Summary → Key Points → Policy Information Table.**
  * Avoid opinion, speculation, or advice; ensure compliance-focused clarity.
  "
)

# Create Group Split tibble ----
file_split_tbl <- tibble(
  file_path = anthem_files
) |>
  mutate(
    file_name = path_file(file_path),
    file_extension = path_ext(file_path),
    file_size = file_size(file_path),
    file_date = file_info(file_path)$modification_time
  ) |>
  group_split(file_name)

# Map over the files and insert into storage ----
llm_resp_list <- file_split_tbl[2:3] |>
  imap(
    .f = function(obj, id) {
      # File path
      file_path <- obj |> pull(1) |> pluck(1)

      # Storage ----
      store_location <- "pdf.ragnar.duckdb"
      store <- ragnar_store_create(
        store_location,
        embed = \(x) embed_ollama(x, model = "nomic-embed-text:latest"),
        overwrite = TRUE
      )

      # Chunking
      chunks <- file_path |>
        read_as_markdown() |>
        markdown_chunk()

      # Insert into storage
      ragnar_store_insert(store, chunks)

      # Build index
      ragnar_store_build_index(store)

      # Chat Client
      # "quen3:0.6b"
      client <- chat_ollama(
        model = "gpt-oss:20b-cloud",
        system_prompt = system_prompt,
        params = list(temperature = 0.1)
      )

      # Set Tool
      ragnar_register_tool_retrieve(
        chat = client,
        store = store
      )

      # Get response
      user_prompt <- glue("Please summarize the policy: {file_path}")
      res <- client$chat(user_prompt, echo = "all")

      # Add response to obj tibble
      rec <- obj |> mutate(llm_resp = res)

      # Return tibble
      return(rec)
    }
  )

output_tbl <- list_rbind(llm_resp_list) |>
  mutate(
    email_body = md(glue(
      "
      Please see summary for below:

      Name: {file_name}

      Extension: {file_extension}
      
      Size: {file_size} bytes
      
      Date: {file_date}

      Summary Response: {llm_resp}
      "
    ))
  )

# Compose Email ----
# Open Outlook
# purr the emails out to whomever
walk(
  .x = output_tbl$email_body,
  ~ {
    Outlook <- COMCreate("Outlook.Application")
    Email <- Outlook$CreateItem(0)
    Email[["subject"]] <- "Payer Policy Summary"
    Email[["htmlbody"]] <- markdown::markdownToHTML(.x)
    attachment <- str_replace_all(
      output_tbl$file_path[output_tbl$email_body == .x],
      "/",
      "\\\\"
    )
    Email[["to"]] <- "spsanderson@gmail.com"
    Email[["attachments"]]$Add(attachment)
    Email$Send()
    rm(Outlook)
    rm(Email)
    Sys.sleep(5)
  }
)

# Testing ----
for (file in anthem_files_subset) {
  chunks <- file |>
    read_as_markdown() |>
    markdown_chunk()

  ragnar_store_insert(store, chunks)
}

ragnar_store_build_index(store)


client <- chat_ollama(
  model = "qwen3:0.6b",
  system_prompt = system_prompt,
  params = list(temperature = 0.1)
)

ragnar_register_tool_retrieve(
  chat = client,
  store = store
)

res <- client$chat("Please summarize the policy.", echo = "none")

"You are an expert assistant in document summarization.
  When responding, you first quote relevant material from the documents in the store,
  provide links to the sources, and then add your own context and interpretation.

  You will provide the following for every document passed to you:
    1. At least three (3) bullet points
    2. A table of information
    3. Summary of the policy
    
    Be concise but thorough."
