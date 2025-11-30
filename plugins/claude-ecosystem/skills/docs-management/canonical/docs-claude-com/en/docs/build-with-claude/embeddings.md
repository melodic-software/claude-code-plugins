<!-- Source: https://docs.claude.com/en/docs/build-with-claude/embeddings -->

# Embeddings

Text embeddings are numerical representations of text that enable measuring semantic similarity. This guide introduces embeddings, their applications, and how to use embedding models for tasks like search, recommendations, and anomaly detection.

## Before implementing embeddings

When selecting an embeddings provider, there are several factors you can consider depending on your needs and preferences:

* Dataset size & domain specificity: size of the model training dataset and its relevance to the domain you want to embed. Larger or more domain-specific data generally produces better in-domain embeddings
* Inference performance: embedding lookup speed and end-to-end latency. This is a particularly important consideration for large scale production deployments
* Customization: options for continued training on private data, or specialization of models for very specific domains. This can improve performance on unique vocabularies

## How to get embeddings with Anthropic

Anthropic does not offer its own embedding model. One embeddings provider that has a wide variety of options and capabilities encompassing all of the above considerations is Voyage AI.

Voyage AI makes state-of-the-art embedding models and offers customized models for specific industry domains such as finance and healthcare, or bespoke fine-tuned models for individual customers.

The rest of this guide is for Voyage AI, but we encourage you to assess a variety of embeddings vendors to find the best fit for your specific use case.

## Available Models

Voyage recommends using the following text embedding models:

| Model              | Context Length | Embedding Dimension            | Description                                                                                                                                                                                                                                           |
| ------------------ | -------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `voyage-3-large`   | 32,000         | 1024 (default), 256, 512, 2048 | The best general-purpose and multilingual retrieval quality. See [blog post](https://blog.voyageai.com/2025/01/07/voyage-3-large/) for details.                                                                                                       |
| `voyage-3.5`       | 32,000         | 1024 (default), 256, 512, 2048 | Optimized for general-purpose and multilingual retrieval quality. See [blog post](https://blog.voyageai.com/2025/05/20/voyage-3-5/) for details.                                                                                                      |
| `voyage-3.5-lite`  | 32,000         | 1024 (default), 256, 512, 2048 | Optimized for latency and cost. See [blog post](https://blog.voyageai.com/2025/05/20/voyage-3-5/) for details.                                                                                                                                        |
| `voyage-code-3`    | 32,000         | 1024 (default), 256, 512, 2048 | Optimized for **code** retrieval. See [blog post](https://blog.voyageai.com/2024/12/04/voyage-code-3/) for details.                                                                                                                                   |
| `voyage-finance-2` | 32,000         | 1024                           | Optimized for **finance** retrieval and RAG. See [blog post](https://blog.voyageai.com/2024/06/03/domain-specific-embeddings-finance-edition-voyage-finance-2/) for details.                                                                          |
| `voyage-law-2`     | 16,000         | 1024                           | Optimized for **legal** and **long-context** retrieval and RAG. Also improved performance across all domains. See [blog post](https://blog.voyageai.com/2024/04/15/domain-specific-embeddings-and-retrieval-legal-edition-voyage-law-2/) for details. |

Additionally, the following multimodal embedding models are recommended:

| Model                 | Context Length | Embedding Dimension | Description                                                                                                                                                                                                                                          |
| --------------------- | -------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `voyage-multimodal-3` | 32000          | 1024                | Rich multimodal embedding model that can vectorize interleaved text and content-rich images, such as screenshots of PDFs, slides, tables, figures, and more. See [blog post](https://blog.voyageai.com/2024/11/12/voyage-multimodal-3/) for details. |

Need help deciding which text embedding model to use? Check out the [FAQ](https://docs.voyageai.com/docs/faq#what-embedding-models-are-available-and-which-one-should-i-use\&ref=anthropic).

## Getting started with Voyage AI

To access Voyage embeddings:

1. Sign up on Voyage AI's website
2. Obtain an API key
3. Set the API key as an environment variable for convenience:

```bash  theme={null}
export VOYAGE_API_KEY="<your secret key>"
```

You can obtain the embeddings by either using the official [`voyageai` Python package](https://github.com/voyage-ai/voyageai-python) or HTTP requests, as described below.

### Voyage Python library

The `voyageai` package can be installed using the following command:

```bash  theme={null}
pip install -U voyageai
```

Then, you can create a client object and start using it to embed your texts:

```python  theme={null}
import voyageai

vo = voyageai.Client()