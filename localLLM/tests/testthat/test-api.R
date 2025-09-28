test_that("API functions are exported", {
  
  # Test that main API functions exist
  expect_true(exists("backend_init"))
  expect_true(exists("backend_free"))
  expect_true(exists("model_load"))
  expect_true(exists("context_create"))
  expect_true(exists("tokenize"))
  expect_true(exists("detokenize"))
  expect_true(exists("generate"))
  expect_true(exists("generate_parallel"))
  
  # Test that functions are actually functions
  expect_type(backend_init, "closure")
  expect_type(backend_free, "closure")
  expect_type(model_load, "closure")
  expect_type(context_create, "closure")
  expect_type(tokenize, "closure")
  expect_type(detokenize, "closure")
  expect_type(generate, "closure")
  expect_type(generate_parallel, "closure")
})

test_that("API functions have correct signatures", {
  
  # Test that functions have the expected number of parameters
  expect_equal(length(formals(backend_init)), 0)
  expect_equal(length(formals(backend_free)), 0)
  expect_gte(length(formals(model_load)), 1)  # At least model_path
  expect_gte(length(formals(context_create)), 1)  # At least model
  expect_gte(length(formals(tokenize)), 2)  # At least context, text
  expect_gte(length(formals(detokenize)), 2)  # At least context, tokens
  expect_gte(length(formals(generate)), 2)  # At least context, prompt
  expect_gte(length(formals(generate_parallel)), 2)  # At least context, prompts
})

test_that("quick_llama functions work", {
  
  # Test that quick_llama functions exist
  expect_true(exists("quick_llama"))
  expect_true(exists("quick_llama_reset"))
  
  # Test that they are functions
  expect_type(quick_llama, "closure")
  expect_type(quick_llama_reset, "closure")
  
  # Test quick_llama_reset (works regardless of backend status)
  # This function only clears cache, doesn't need backend
  expect_message(quick_llama_reset(), "quick_llama state reset")
})