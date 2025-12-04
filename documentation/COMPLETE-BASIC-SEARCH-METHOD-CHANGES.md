# Complete `basic_search` Method Changes

## 📍 File Location

**File:** `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`

**Function:** `basic_search` (starts at line 47)

---

## 📋 Complete OLD `basic_search` Method (Current Code)

Here's the **entire function as it currently exists** (lines 47-344):

```python
def basic_search(
    state: BranchInput,
    config: RunnableConfig,
    writer: StreamWriter = lambda _: None,
) -> BranchUpdate:
    """
    LangGraph node to perform a standard search as part of the DR process.
    """

    node_start_time = datetime.now()
    iteration_nr = state.iteration_nr
    parallelization_nr = state.parallelization_nr
    current_step_nr = state.current_step_nr
    assistant_system_prompt = state.assistant_system_prompt
    assistant_task_prompt = state.assistant_task_prompt

    branch_query = state.branch_question
    if not branch_query:
        raise ValueError("branch_query is not set")

    graph_config = cast(GraphConfig, config["metadata"]["config"])
    base_question = graph_config.inputs.prompt_builder.raw_user_query
    research_type = graph_config.behavior.research_type

    if not state.available_tools:
        raise ValueError("available_tools is not set")

    elif len(state.tools_used) == 0:
        raise ValueError("tools_used is empty")

    search_tool_info = state.available_tools[state.tools_used[-1]]
    search_tool = cast(SearchTool, search_tool_info.tool_object)
    force_use_tool = graph_config.tooling.force_use_tool

    # sanity check
    if search_tool != graph_config.tooling.search_tool:
        raise ValueError("search_tool does not match the configured search tool")

    # Check if we have user_file_ids from override_kwargs (before query rewriting)
    user_file_ids: list[UUID] | None = None
    project_id: int | None = None
    if force_use_tool.override_kwargs and isinstance(
        force_use_tool.override_kwargs, SearchToolOverrideKwargs
    ):
        override_kwargs = force_use_tool.override_kwargs
        user_file_ids = override_kwargs.user_file_ids
        project_id = override_kwargs.project_id

    # If we have user_file_ids, skip query rewriting and use original query
    # Query rewriting can make the query too generic or extract wrong source types,
    # causing the first search attempt to fail even though the file is indexed.
    # Using the original query directly ensures consistent, reliable results.
    if user_file_ids:
        # For user file searches, use the original query directly
        rewritten_query = branch_query
        specified_source_types: list[DocumentSource] | None = [DocumentSource.USER_FILE]
        implied_time_filter = None
        logger.debug(
            f"Skipping query rewriting for user file search with {len(user_file_ids)} files. "
            f"Using original query: {branch_query}"
        )
    else:
        # Original query rewriting logic for general searches
        # rewrite query and identify source types
        active_source_types_str = ", ".join(
            [source.value for source in state.active_source_types or []]
        )

        base_search_processing_prompt = BASE_SEARCH_PROCESSING_PROMPT.build(
            active_source_types_str=active_source_types_str,
            branch_query=branch_query,
            current_time=datetime.now().strftime("%Y-%m-%d %H:%M"),
        )

        try:
            search_processing = invoke_llm_json(
                llm=graph_config.tooling.primary_llm,
                prompt=create_question_prompt(
                    assistant_system_prompt, base_search_processing_prompt
                ),
                schema=BaseSearchProcessingResponse,
                timeout_override=TF_DR_TIMEOUT_SHORT,
                # max_tokens=100,
            )
        except Exception as e:
            logger.error(f"Could not process query: {e}")
            raise e

        rewritten_query = search_processing.rewritten_query

        implied_start_date = search_processing.time_filter

        # Validate time_filter format if it exists
        implied_time_filter = None
        if implied_start_date:

            # Check if time_filter is in YYYY-MM-DD format
            date_pattern = r"^\d{4}-\d{2}-\d{2}$"
            if re.match(date_pattern, implied_start_date):
                implied_time_filter = datetime.strptime(implied_start_date, "%Y-%m-%d")

        specified_source_types: list[DocumentSource] | None = (
            strings_to_document_sources(search_processing.specified_source_types)
            if search_processing.specified_source_types
            else None
        )

        if specified_source_types is not None and len(specified_source_types) == 0:
            specified_source_types = None

    # give back the query so we can render it in the UI
    write_custom_event(
        current_step_nr,
        SearchToolDelta(
            queries=[rewritten_query],
            documents=[],
        ),
        writer,
    )

    logger.debug(
        f"Search start for Standard Search {iteration_nr}.{parallelization_nr} at {datetime.now()}"
    )

    retrieved_docs: list[InferenceSection] = []
    callback_container: list[list[InferenceSection]] = []

    # new db session to avoid concurrency issues
    with get_session_with_current_tenant() as search_db_session:
        for tool_response in search_tool.run(
            query=rewritten_query,
            document_sources=specified_source_types,
            time_filter=implied_time_filter,
            override_kwargs=SearchToolOverrideKwargs(
                force_no_rerank=True,
                alternate_db_session=search_db_session,
                retrieved_sections_callback=callback_container.append,
                skip_query_analysis=True,
                original_query=rewritten_query,
                user_file_ids=user_file_ids,
                project_id=project_id,
            ),
        ):
            # get retrieved docs to send to the rest of the graph
            if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                response = cast(SearchResponseSummary, tool_response.response)
                retrieved_docs = response.top_sections

                break

        # If we have user_file_ids but got no results, retry after short delay
        # This handles Vespa eventual consistency - chunks may be written but not searchable yet
        if user_file_ids and len(retrieved_docs) == 0:
            logger.warning(
                f"Search returned no results for user_file_ids {user_file_ids} on first attempt. "
                f"Retrying after 1 second to handle Vespa eventual consistency..."
            )
            sleep(1.0)  # Wait 1 second for Vespa index to update

            # Retry the search
            callback_container.clear()  # Clear previous callback results
            for tool_response in search_tool.run(
                query=rewritten_query,
                document_sources=specified_source_types,
                time_filter=implied_time_filter,
                override_kwargs=SearchToolOverrideKwargs(
                    force_no_rerank=True,
                    alternate_db_session=search_db_session,
                    retrieved_sections_callback=callback_container.append,
                    skip_query_analysis=True,
                    original_query=rewritten_query,
                    user_file_ids=user_file_ids,
                    project_id=project_id,
                ),
            ):
                if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                    response = cast(SearchResponseSummary, tool_response.response)
                    retrieved_docs = response.top_sections
                    break

            if len(retrieved_docs) > 0:
                logger.info(
                    f"Retry successful! Found {len(retrieved_docs)} chunks for user_file_ids {user_file_ids}"
                )
            else:
                logger.warning(
                    f"Retry still returned no results for user_file_ids {user_file_ids}. "
                    f"File may not be fully indexed yet."
                )

    # render the retrieved docs in the UI
    write_custom_event(
        current_step_nr,
        SearchToolDelta(
            queries=[],
            documents=convert_inference_sections_to_search_docs(
                retrieved_docs, is_internet=False
            ),
        ),
        writer,
    )

    document_texts_list = []

    for doc_num, retrieved_doc in enumerate(retrieved_docs[:15]):
        if not isinstance(retrieved_doc, (InferenceSection, LlmDoc)):
            raise ValueError(f"Unexpected document type: {type(retrieved_doc)}")
        chunk_text = build_document_context(retrieved_doc, doc_num + 1)
        document_texts_list.append(chunk_text)

    document_texts = "\n\n".join(document_texts_list)

    logger.debug(
        f"Search end/LLM start for Standard Search {iteration_nr}.{parallelization_nr} at {datetime.now()}"
    )

    # Built prompt

    if research_type == ResearchType.DEEP:
        search_prompt = INTERNAL_SEARCH_PROMPTS[research_type].build(
            search_query=branch_query,
            base_question=base_question,
            document_text=document_texts,
        )

        # Run LLM

        # search_answer_json = None
        search_answer_json = invoke_llm_json(
            llm=graph_config.tooling.primary_llm,
            prompt=create_question_prompt(
                assistant_system_prompt, search_prompt + (assistant_task_prompt or "")
            ),
            schema=SearchAnswer,
            timeout_override=TF_DR_TIMEOUT_LONG,
            # max_tokens=1500,
        )

        logger.debug(
            f"LLM/all done for Standard Search {iteration_nr}.{parallelization_nr} at {datetime.now()}"
        )

        # get cited documents
        answer_string = search_answer_json.answer
        claims = search_answer_json.claims or []
        reasoning = search_answer_json.reasoning
        # answer_string = ""
        # claims = []

        (
            citation_numbers,
            answer_string,
            claims,
        ) = extract_document_citations(answer_string, claims)

        if citation_numbers and (
            (max(citation_numbers) > len(retrieved_docs)) or min(citation_numbers) < 1
        ):
            raise ValueError("Citation numbers are out of range for retrieved docs.")

        cited_documents = {
            citation_number: retrieved_docs[citation_number - 1]
            for citation_number in citation_numbers
        }

    else:
        answer_string = ""
        claims = []
        cited_documents = {
            doc_num + 1: retrieved_doc
            for doc_num, retrieved_doc in enumerate(retrieved_docs[:15])
        }
        reasoning = ""

    return BranchUpdate(
        branch_iteration_responses=[
            IterationAnswer(
                tool=search_tool_info.llm_path,
                tool_id=search_tool_info.tool_id,
                iteration_nr=iteration_nr,
                parallelization_nr=parallelization_nr,
                question=branch_query,
                answer=answer_string,
                claims=claims,
                cited_documents=cited_documents,
                reasoning=reasoning,
                additional_data=None,
            )
        ],
        log_messages=[
            get_langgraph_node_log_string(
                graph_component="basic_search",
                node_name="searching",
                node_start_time=node_start_time,
            )
        ],
    )
```

---

## ✅ Complete NEW `basic_search` Method (With Multiple Retries)

Here's the **entire function with the improved retry logic** - the only change is in the retry section (lines 197-235):

```python
def basic_search(
    state: BranchInput,
    config: RunnableConfig,
    writer: StreamWriter = lambda _: None,
) -> BranchUpdate:
    """
    LangGraph node to perform a standard search as part of the DR process.
    """

    node_start_time = datetime.now()
    iteration_nr = state.iteration_nr
    parallelization_nr = state.parallelization_nr
    current_step_nr = state.current_step_nr
    assistant_system_prompt = state.assistant_system_prompt
    assistant_task_prompt = state.assistant_task_prompt

    branch_query = state.branch_question
    if not branch_query:
        raise ValueError("branch_query is not set")

    graph_config = cast(GraphConfig, config["metadata"]["config"])
    base_question = graph_config.inputs.prompt_builder.raw_user_query
    research_type = graph_config.behavior.research_type

    if not state.available_tools:
        raise ValueError("available_tools is not set")

    elif len(state.tools_used) == 0:
        raise ValueError("tools_used is empty")

    search_tool_info = state.available_tools[state.tools_used[-1]]
    search_tool = cast(SearchTool, search_tool_info.tool_object)
    force_use_tool = graph_config.tooling.force_use_tool

    # sanity check
    if search_tool != graph_config.tooling.search_tool:
        raise ValueError("search_tool does not match the configured search tool")

    # Check if we have user_file_ids from override_kwargs (before query rewriting)
    user_file_ids: list[UUID] | None = None
    project_id: int | None = None
    if force_use_tool.override_kwargs and isinstance(
        force_use_tool.override_kwargs, SearchToolOverrideKwargs
    ):
        override_kwargs = force_use_tool.override_kwargs
        user_file_ids = override_kwargs.user_file_ids
        project_id = override_kwargs.project_id

    # If we have user_file_ids, skip query rewriting and use original query
    # Query rewriting can make the query too generic or extract wrong source types,
    # causing the first search attempt to fail even though the file is indexed.
    # Using the original query directly ensures consistent, reliable results.
    if user_file_ids:
        # For user file searches, use the original query directly
        rewritten_query = branch_query
        specified_source_types: list[DocumentSource] | None = [DocumentSource.USER_FILE]
        implied_time_filter = None
        logger.debug(
            f"Skipping query rewriting for user file search with {len(user_file_ids)} files. "
            f"Using original query: {branch_query}"
        )
    else:
        # Original query rewriting logic for general searches
        # rewrite query and identify source types
        active_source_types_str = ", ".join(
            [source.value for source in state.active_source_types or []]
        )

        base_search_processing_prompt = BASE_SEARCH_PROCESSING_PROMPT.build(
            active_source_types_str=active_source_types_str,
            branch_query=branch_query,
            current_time=datetime.now().strftime("%Y-%m-%d %H:%M"),
        )

        try:
            search_processing = invoke_llm_json(
                llm=graph_config.tooling.primary_llm,
                prompt=create_question_prompt(
                    assistant_system_prompt, base_search_processing_prompt
                ),
                schema=BaseSearchProcessingResponse,
                timeout_override=TF_DR_TIMEOUT_SHORT,
                # max_tokens=100,
            )
        except Exception as e:
            logger.error(f"Could not process query: {e}")
            raise e

        rewritten_query = search_processing.rewritten_query

        implied_start_date = search_processing.time_filter

        # Validate time_filter format if it exists
        implied_time_filter = None
        if implied_start_date:

            # Check if time_filter is in YYYY-MM-DD format
            date_pattern = r"^\d{4}-\d{2}-\d{2}$"
            if re.match(date_pattern, implied_start_date):
                implied_time_filter = datetime.strptime(implied_start_date, "%Y-%m-%d")

        specified_source_types: list[DocumentSource] | None = (
            strings_to_document_sources(search_processing.specified_source_types)
            if search_processing.specified_source_types
            else None
        )

        if specified_source_types is not None and len(specified_source_types) == 0:
            specified_source_types = None

    # give back the query so we can render it in the UI
    write_custom_event(
        current_step_nr,
        SearchToolDelta(
            queries=[rewritten_query],
            documents=[],
        ),
        writer,
    )

    logger.debug(
        f"Search start for Standard Search {iteration_nr}.{parallelization_nr} at {datetime.now()}"
    )

    retrieved_docs: list[InferenceSection] = []
    callback_container: list[list[InferenceSection]] = []

    # new db session to avoid concurrency issues
    with get_session_with_current_tenant() as search_db_session:
        for tool_response in search_tool.run(
            query=rewritten_query,
            document_sources=specified_source_types,
            time_filter=implied_time_filter,
            override_kwargs=SearchToolOverrideKwargs(
                force_no_rerank=True,
                alternate_db_session=search_db_session,
                retrieved_sections_callback=callback_container.append,
                skip_query_analysis=True,
                original_query=rewritten_query,
                user_file_ids=user_file_ids,
                project_id=project_id,
            ),
        ):
            # get retrieved docs to send to the rest of the graph
            if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                response = cast(SearchResponseSummary, tool_response.response)
                retrieved_docs = response.top_sections

                break

        # If we have user_file_ids but got no results, retry with exponential backoff
        # This handles Vespa eventual consistency - chunks may be written but not searchable yet
        if user_file_ids and len(retrieved_docs) == 0:
            max_retries = 3
            retry_delays = [1.0, 2.0, 3.0]  # Exponential backoff: 1s, 2s, 3s
            
            for retry_num in range(max_retries):
                logger.warning(
                    f"Search returned no results for user_file_ids {user_file_ids} on attempt {retry_num + 1}. "
                    f"Retrying after {retry_delays[retry_num]}s to handle Vespa eventual consistency..."
                )
                sleep(retry_delays[retry_num])
                
                # Retry the search
                callback_container.clear()  # Clear previous callback results
                for tool_response in search_tool.run(
                    query=rewritten_query,
                    document_sources=specified_source_types,
                    time_filter=implied_time_filter,
                    override_kwargs=SearchToolOverrideKwargs(
                        force_no_rerank=True,
                        alternate_db_session=search_db_session,
                        retrieved_sections_callback=callback_container.append,
                        skip_query_analysis=True,
                        original_query=rewritten_query,
                        user_file_ids=user_file_ids,
                        project_id=project_id,
                    ),
                ):
                    if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                        response = cast(SearchResponseSummary, tool_response.response)
                        retrieved_docs = response.top_sections
                        break
                
                if len(retrieved_docs) > 0:
                    logger.info(
                        f"Retry {retry_num + 1} successful! Found {len(retrieved_docs)} chunks "
                        f"for user_file_ids {user_file_ids}"
                    )
                    break
                else:
                    logger.warning(
                        f"Retry {retry_num + 1} still returned no results for user_file_ids {user_file_ids}."
                    )
            
            if len(retrieved_docs) == 0:
                logger.error(
                    f"All {max_retries} retries exhausted. File may not be fully indexed yet "
                    f"for user_file_ids {user_file_ids}."
                )

    # render the retrieved docs in the UI
    write_custom_event(
        current_step_nr,
        SearchToolDelta(
            queries=[],
            documents=convert_inference_sections_to_search_docs(
                retrieved_docs, is_internet=False
            ),
        ),
        writer,
    )

    document_texts_list = []

    for doc_num, retrieved_doc in enumerate(retrieved_docs[:15]):
        if not isinstance(retrieved_doc, (InferenceSection, LlmDoc)):
            raise ValueError(f"Unexpected document type: {type(retrieved_doc)}")
        chunk_text = build_document_context(retrieved_doc, doc_num + 1)
        document_texts_list.append(chunk_text)

    document_texts = "\n\n".join(document_texts_list)

    logger.debug(
        f"Search end/LLM start for Standard Search {iteration_nr}.{parallelization_nr} at {datetime.now()}"
    )

    # Built prompt

    if research_type == ResearchType.DEEP:
        search_prompt = INTERNAL_SEARCH_PROMPTS[research_type].build(
            search_query=branch_query,
            base_question=base_question,
            document_text=document_texts,
        )

        # Run LLM

        # search_answer_json = None
        search_answer_json = invoke_llm_json(
            llm=graph_config.tooling.primary_llm,
            prompt=create_question_prompt(
                assistant_system_prompt, search_prompt + (assistant_task_prompt or "")
            ),
            schema=SearchAnswer,
            timeout_override=TF_DR_TIMEOUT_LONG,
            # max_tokens=1500,
        )

        logger.debug(
            f"LLM/all done for Standard Search {iteration_nr}.{parallelization_nr} at {datetime.now()}"
        )

        # get cited documents
        answer_string = search_answer_json.answer
        claims = search_answer_json.claims or []
        reasoning = search_answer_json.reasoning
        # answer_string = ""
        # claims = []

        (
            citation_numbers,
            answer_string,
            claims,
        ) = extract_document_citations(answer_string, claims)

        if citation_numbers and (
            (max(citation_numbers) > len(retrieved_docs)) or min(citation_numbers) < 1
        ):
            raise ValueError("Citation numbers are out of range for retrieved docs.")

        cited_documents = {
            citation_number: retrieved_docs[citation_number - 1]
            for citation_number in citation_numbers
        }

    else:
        answer_string = ""
        claims = []
        cited_documents = {
            doc_num + 1: retrieved_doc
            for doc_num, retrieved_doc in enumerate(retrieved_docs[:15])
        }
        reasoning = ""

    return BranchUpdate(
        branch_iteration_responses=[
            IterationAnswer(
                tool=search_tool_info.llm_path,
                tool_id=search_tool_info.tool_id,
                iteration_nr=iteration_nr,
                parallelization_nr=parallelization_nr,
                question=branch_query,
                answer=answer_string,
                claims=claims,
                cited_documents=cited_documents,
                reasoning=reasoning,
                additional_data=None,
            )
        ],
        log_messages=[
            get_langgraph_node_log_string(
                graph_component="basic_search",
                node_name="searching",
                node_start_time=node_start_time,
            )
        ],
    )
```

---

## 🔍 What Changed? (Only the Retry Section)

### **OLD CODE (Lines 197-235):**

```python
        # If we have user_file_ids but got no results, retry after short delay
        # This handles Vespa eventual consistency - chunks may be written but not searchable yet
        if user_file_ids and len(retrieved_docs) == 0:
            logger.warning(
                f"Search returned no results for user_file_ids {user_file_ids} on first attempt. "
                f"Retrying after 1 second to handle Vespa eventual consistency..."
            )
            sleep(1.0)  # Wait 1 second for Vespa index to update

            # Retry the search
            callback_container.clear()  # Clear previous callback results
            for tool_response in search_tool.run(
                query=rewritten_query,
                document_sources=specified_source_types,
                time_filter=implied_time_filter,
                override_kwargs=SearchToolOverrideKwargs(
                    force_no_rerank=True,
                    alternate_db_session=search_db_session,
                    retrieved_sections_callback=callback_container.append,
                    skip_query_analysis=True,
                    original_query=rewritten_query,
                    user_file_ids=user_file_ids,
                    project_id=project_id,
                ),
            ):
                if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                    response = cast(SearchResponseSummary, tool_response.response)
                    retrieved_docs = response.top_sections
                    break

            if len(retrieved_docs) > 0:
                logger.info(
                    f"Retry successful! Found {len(retrieved_docs)} chunks for user_file_ids {user_file_ids}"
                )
            else:
                logger.warning(
                    f"Retry still returned no results for user_file_ids {user_file_ids}. "
                    f"File may not be fully indexed yet."
                )
```

### **NEW CODE (Replace the entire section above with this):**

```python
        # If we have user_file_ids but got no results, retry with exponential backoff
        # This handles Vespa eventual consistency - chunks may be written but not searchable yet
        if user_file_ids and len(retrieved_docs) == 0:
            max_retries = 3
            retry_delays = [1.0, 2.0, 3.0]  # Exponential backoff: 1s, 2s, 3s
            
            for retry_num in range(max_retries):
                logger.warning(
                    f"Search returned no results for user_file_ids {user_file_ids} on attempt {retry_num + 1}. "
                    f"Retrying after {retry_delays[retry_num]}s to handle Vespa eventual consistency..."
                )
                sleep(retry_delays[retry_num])
                
                # Retry the search
                callback_container.clear()  # Clear previous callback results
                for tool_response in search_tool.run(
                    query=rewritten_query,
                    document_sources=specified_source_types,
                    time_filter=implied_time_filter,
                    override_kwargs=SearchToolOverrideKwargs(
                        force_no_rerank=True,
                        alternate_db_session=search_db_session,
                        retrieved_sections_callback=callback_container.append,
                        skip_query_analysis=True,
                        original_query=rewritten_query,
                        user_file_ids=user_file_ids,
                        project_id=project_id,
                    ),
                ):
                    if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                        response = cast(SearchResponseSummary, tool_response.response)
                        retrieved_docs = response.top_sections
                        break
                
                if len(retrieved_docs) > 0:
                    logger.info(
                        f"Retry {retry_num + 1} successful! Found {len(retrieved_docs)} chunks "
                        f"for user_file_ids {user_file_ids}"
                    )
                    break
                else:
                    logger.warning(
                        f"Retry {retry_num + 1} still returned no results for user_file_ids {user_file_ids}."
                    )
            
            if len(retrieved_docs) == 0:
                logger.error(
                    f"All {max_retries} retries exhausted. File may not be fully indexed yet "
                    f"for user_file_ids {user_file_ids}."
                )
```

---

## 📝 Step-by-Step Instructions

### **Step 1: Open the File**
1. Navigate to: `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`
2. Open it in your code editor

### **Step 2: Find the Retry Section**
1. Find the `basic_search` function (starts at line 47)
2. Scroll down to around **line 197**
3. Look for the comment: `# If we have user_file_ids but got no results, retry after short delay`
4. This section goes from line 197 to line 235

### **Step 3: Replace the Retry Section**
1. **Select everything from line 197 to line 235** (the entire retry block)
2. **Delete it**
3. **Replace with the NEW CODE** from above (the multiple retries with exponential backoff)
4. Make sure the indentation is correct (should be inside the `with get_session_with_current_tenant() as search_db_session:` block)

### **Step 4: Verify**
1. The rest of the function should be **unchanged**
2. The function should still end with `return BranchUpdate(...)` at the end
3. Make sure there are no syntax errors

---

## 🎯 Key Changes Summary

| What | Before | After |
|------|--------|-------|
| **Number of retries** | 1 retry | 3 retries |
| **Delay** | Fixed 1 second | Exponential backoff: 1s, 2s, 3s |
| **Loop structure** | Single `if` block | `for` loop with `max_retries` |
| **Success detection** | After retry | Breaks immediately when successful |
| **Error logging** | Warning if fails | Error log after all retries exhausted |

---

## ✅ Expected Behavior

### **Before Fix:**
- First search attempt: No results
- One retry after 1 second: May or may not find results
- If still no results: Gives up

### **After Fix:**
- First search attempt: No results
- Retry 1 after 1 second: May find results (if yes, stops)
- Retry 2 after 2 seconds: May find results (if yes, stops)
- Retry 3 after 3 seconds: May find results (if yes, stops)
- If all retries fail: Logs error and continues (but with empty results)

---

## 📊 Visual Comparison

### **BEFORE:**
```
if user_file_ids and len(retrieved_docs) == 0:
    logger.warning("...first attempt...")
    sleep(1.0)  ← Single delay
    [retry search]
    if len(retrieved_docs) > 0:
        logger.info("Retry successful!")
    else:
        logger.warning("Retry still returned no results.")
```

### **AFTER:**
```
if user_file_ids and len(retrieved_docs) == 0:
    max_retries = 3
    retry_delays = [1.0, 2.0, 3.0]  ← Multiple delays
    
    for retry_num in range(max_retries):  ← Loop
        logger.warning("...attempt {retry_num + 1}...")
        sleep(retry_delays[retry_num])  ← Exponential backoff
        [retry search]
        if len(retrieved_docs) > 0:
            logger.info("Retry {retry_num + 1} successful!")
            break  ← Stop immediately if successful
        else:
            logger.warning("Retry {retry_num + 1} still returned no results.")
    
    if len(retrieved_docs) == 0:  ← Final check
        logger.error("All retries exhausted.")
```

---

**That's it!** The function now retries up to 3 times with increasing delays, which should significantly improve the success rate for finding documents on the first prompt.


