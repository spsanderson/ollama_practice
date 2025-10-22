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
llm_resp_list <- file_split_tbl[1:3] |>
  imap(
    .f = function(obj, id) {
      # File path
      file_path <- obj |> pull(1) |> pluck(1)

      # Storage ----
      store_location <- "pdf_ragnar_duckdb"
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

      Summary Response: 

      {llm_resp}
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
    Email[["to"]] <- ""
    Email[["attachments"]]$Add(attachment)
    Email$Send()
    rm(Outlook)
    rm(Email)
    Sys.sleep(5)
  }
)

# Single file ---
# Function to convert a single row to markdown
row_to_md <- function(row) {
  # Convert fs::bytes to character
  file_size_str <- as.character(row$file_size)
  # Convert dttm to date string
  file_date_str <- as.character(row$file_date)
  # Convert other columns to character
  llm_resp_str <- as.character(row$llm_resp)
  email_body_str <- as.character(row$email_body)

row_to_md <- function(row) {
  # Convert fs::bytes to character
  file_size_str <- as.character(row$file_size)
  # Convert dttm to date string
  file_date_str <- as.character(row$file_date)
  # Convert other columns to character
  llm_resp_str <- as.character(row$llm_resp)
  email_body_str <- as.character(row$email_body)
  
  md <- paste0(
    '**File Path:** "', row$file_path, '"\n\n',
    '**File Name:** "', row$file_name, '"\n\n',
    '**File Extension:** "', row$file_extension, '\n\n',
    '**File Size:** ', file_size_str, '\n\n',
    '**File Date:** ', file_date_str, '\n\n',
    '**LLM Response:** "', llm_resp_str, '"\n\n'
    #'**Email Body:** "', email_body_str, '"\n\n'
  )
  return(md)
}

# Apply to all rows and separate with ---
markdown_sections <- map_chr(1:nrow(output_tbl), function(i) {
  row_to_md(output_tbl[i, ])
})
markdown_doc <- paste(markdown_sections, collapse = "\n---\n")

# Write to file
write_file(markdown_doc, paste0(getwd(), "/policy_output.md"))

# Testing ----
anthem_files_subset <- anthem_files[2]

# Storage ----
store_location <- "pdf_ragnar_duckdb"
store <- ragnar_store_create(
  store_location,
  embed = \(x) embed_ollama(x, model = "nomic-embed-text:latest"),
  overwrite = TRUE
)

for (file in anthem_files_subset) {
  chunks <- file |>
    read_as_markdown() |>
    markdown_chunk()

  ragnar_store_insert(store, chunks)

  # Build index
  ragnar_store_build_index(store)
}

client <- chat_ollama(
  model = "llama3.2",
  system_prompt = system_prompt,
  params = list(temperature = 0.1)
)

ragnar_register_tool_retrieve(
  chat = client,
  store = store
)

res <- client$chat("Please summarize the policy.", echo = "all")
print(res)

"You are an expert assistant in document summarization.
  When responding, you first quote relevant material from the documents in the store,
  provide links to the sources, and then add your own context and interpretation.

  You will provide the following for every document passed to you:
    1. At least three (3) bullet points
    2. A table of information
    3. Summary of the policy
    
    Be concise but thorough."
