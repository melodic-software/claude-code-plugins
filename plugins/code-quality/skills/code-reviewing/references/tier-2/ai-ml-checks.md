# AI/ML Code Review Checks

## Overview

This document provides comprehensive AI/ML-specific code review checks for machine learning codebases, notebooks, and model deployments.

**Loaded when reviewing:**

- `.ipynb` files (Jupyter notebooks)
- Files in `model/*`, `ml/*`, `ai/*`, `models/*`, `training/*` directories
- Files with ML patterns (tensorflow, pytorch, sklearn, keras imports)

## 1. Model Versioning and Reproducibility

- [ ] **Model versioning** - Models are versioned using MLflow, DVC, or similar tools with semantic versioning
- [ ] **Experiment tracking** - All training runs logged with hyperparameters, metrics, and artifacts (MLflow, Weights & Biases, TensorBoard)
- [ ] **Random seed setting** - All random seeds fixed for reproducibility (numpy, random, torch, tf)
- [ ] **Dependency pinning** - Exact versions pinned for ML libraries (tensorflow==2.x.x, torch==2.x.x, not >=)
- [ ] **Environment reproducibility** - Docker/conda environment specs committed alongside code
- [ ] **Data versioning** - Training/validation/test data versioned with DVC, MLflow, or equivalent
- [ ] **Model registry** - Trained models registered in central registry with metadata (accuracy, training date, dataset version)
- [ ] **Checkpoint management** - Training checkpoints saved at configurable intervals with automatic cleanup of old checkpoints

## 2. Data Pipeline Validation

- [ ] **Data schema validation** - Input data validated against expected schema (pandera, great_expectations, TFX)
- [ ] **Missing value handling** - Explicit strategy for missing values (drop, impute, flag) documented and implemented
- [ ] **Outlier detection** - Outliers detected and handled appropriately (cap, remove, flag)
- [ ] **Data splits** - Train/val/test splits properly separated with no data leakage between sets
- [ ] **Data augmentation reproducibility** - Augmentation pipelines reproducible with fixed seeds when needed
- [ ] **Data loading efficiency** - Data loaded efficiently (batching, prefetching, caching) to avoid training bottlenecks
- [ ] **Data quality monitoring** - Data quality metrics tracked over time (missing rates, distribution shifts, anomaly counts)
- [ ] **Class imbalance handling** - Imbalanced datasets handled appropriately (resampling, class weights, focal loss)

## 3. Feature Engineering

- [ ] **Feature documentation** - All features documented with name, type, source, and business meaning
- [ ] **Feature scaling** - Numerical features scaled/normalized appropriately (StandardScaler, MinMaxScaler)
- [ ] **Categorical encoding** - Categorical variables encoded correctly (one-hot, label encoding, embeddings) based on cardinality
- [ ] **Feature leakage prevention** - Features engineered from training set only, then applied to validation/test (no fit_transform on test)
- [ ] **Feature importance tracking** - Feature importance logged and monitored across model versions
- [ ] **Time-based features** - Temporal features respect train/test split chronology (no future information leak)
- [ ] **Feature store integration** - Features registered in feature store (Feast, Tecton) for reuse across models
- [ ] **Feature validation** - Features validated for type, range, nullability before training

## 4. Model Training and Evaluation

- [ ] **Baseline model** - Simple baseline model (mean/median/mode predictor) established before complex models
- [ ] **Cross-validation** - Cross-validation used appropriately (k-fold, stratified, time-series split) to assess generalization
- [ ] **Metric selection** - Evaluation metrics appropriate for problem type (classification: precision/recall/F1/AUC, regression: RMSE/MAE/R²)
- [ ] **Overfitting detection** - Training vs validation metrics monitored to detect overfitting early
- [ ] **Early stopping** - Early stopping implemented to prevent overfitting and save compute
- [ ] **Hyperparameter tuning** - Hyperparameters tuned systematically (grid search, random search, Bayesian optimization)
- [ ] **Learning curve analysis** - Learning curves plotted to diagnose bias/variance tradeoff
- [ ] **Model comparison** - Multiple models compared on same validation set with statistical significance tests when appropriate

## 5. Bias and Fairness

- [ ] **Fairness metrics** - Fairness metrics calculated across protected groups (demographic parity, equalized odds, calibration)
- [ ] **Bias detection** - Training data analyzed for representation bias across demographics
- [ ] **Disparate impact analysis** - Model predictions analyzed for disparate impact on protected groups
- [ ] **Fairness-aware training** - Fairness constraints or regularization applied if needed (adversarial debiasing, reweighting)
- [ ] **Interpretability** - Model interpretability tools used (SHAP, LIME, integrated gradients) to understand feature impact
- [ ] **Documentation of limitations** - Known biases and model limitations documented explicitly
- [ ] **Human-in-the-loop** - High-stakes decisions include human review rather than full automation

## 6. Model Deployment and Serving

- [ ] **Model serialization** - Models serialized in portable format (ONNX, SavedModel, pickle) with version metadata
- [ ] **Inference API design** - Inference API follows REST/gRPC best practices with proper error handling
- [ ] **Input validation** - API validates input schema, types, ranges before inference
- [ ] **Batch vs online inference** - Appropriate inference mode chosen (batch for high throughput, online for low latency)
- [ ] **Model warm-up** - Model pre-loaded and warmed up before serving traffic
- [ ] **Graceful degradation** - Fallback strategy defined when model unavailable (cached predictions, simple heuristic)
- [ ] **A/B testing support** - Infrastructure supports A/B testing of model versions
- [ ] **Canary deployments** - New models deployed incrementally (1% → 10% → 100% traffic)

## 7. Inference Optimization

- [ ] **Model quantization** - Models quantized (int8, float16) when appropriate to reduce latency and memory
- [ ] **Model pruning** - Unnecessary weights pruned to reduce model size
- [ ] **Batching** - Inference batching implemented to maximize GPU utilization
- [ ] **Caching** - Frequently requested predictions cached with appropriate TTL
- [ ] **Hardware acceleration** - Models compiled for target hardware (TensorRT, CoreML, ONNX Runtime)
- [ ] **Latency budgets** - Inference latency budgets defined and monitored (p50, p95, p99)
- [ ] **Throughput optimization** - Throughput optimized for expected request volume
- [ ] **Memory management** - Model memory usage monitored and optimized to avoid OOM errors

## 8. Model Monitoring and Observability

- [ ] **Prediction logging** - Predictions logged with input features, timestamp, model version
- [ ] **Latency monitoring** - Inference latency tracked (p50, p95, p99) with alerting on regressions
- [ ] **Throughput monitoring** - Request volume and throughput monitored
- [ ] **Model drift detection** - Input distribution drift detected (KL divergence, PSI, Kolmogorov-Smirnov test)
- [ ] **Performance degradation alerts** - Model performance monitored on live data with alerts on accuracy drops
- [ ] **Data quality monitoring** - Input data quality monitored (missing rates, out-of-range values, schema violations)
- [ ] **Concept drift detection** - Target variable distribution monitored for shifts
- [ ] **Retraining triggers** - Automated retraining triggered when drift or performance degradation detected

## 9. Data Privacy and Security

- [ ] **PII handling** - Personally identifiable information (PII) identified, minimized, and protected
- [ ] **Data encryption** - Sensitive data encrypted at rest and in transit
- [ ] **Differential privacy** - Differential privacy applied when training on sensitive data
- [ ] **Federated learning** - Federated learning used when data cannot be centralized
- [ ] **Model privacy** - Model inversion and membership inference attacks mitigated
- [ ] **Access controls** - Data access restricted by role with audit logging
- [ ] **GDPR compliance** - Right to explanation and right to be forgotten supported when applicable
- [ ] **Data retention policies** - Training data and predictions retained only as long as necessary

## 10. Notebook Best Practices

- [ ] **Linear execution** - Notebooks executable top-to-bottom without hidden state dependencies
- [ ] **Cell organization** - Logical grouping of cells with markdown headers explaining each section
- [ ] **No magic numbers** - Constants defined at top of notebook, not scattered throughout cells
- [ ] **Reproducibility** - Random seeds set at beginning; notebook produces same results on re-run
- [ ] **Environment specification** - Required packages listed in requirements.txt or environment.yml
- [ ] **Output clearing** - Large outputs cleared before committing to avoid bloating repo size
- [ ] **Code extraction** - Reusable code extracted to .py modules rather than duplicated across notebooks
- [ ] **Visualization quality** - Plots include titles, axis labels, legends, and appropriate scales
- [ ] **Notebook testing** - Notebooks tested with nbconvert or papermill for execution errors
- [ ] **Documentation** - Markdown cells explain methodology, assumptions, and findings

## 11. ML Code Quality

- [ ] **Type hints** - Type hints used for model inputs, outputs, and key functions
- [ ] **Error handling** - Training failures handled gracefully with checkpoints and restart capability
- [ ] **Logging** - Structured logging used (not print statements) with appropriate log levels
- [ ] **Configuration management** - Hyperparameters and configs managed externally (YAML, JSON, Hydra) not hardcoded
- [ ] **Modularity** - Training pipeline modular (data loading, preprocessing, training, evaluation) for reusability
- [ ] **Testing** - Unit tests for data processing, feature engineering, and custom layers/losses
- [ ] **Code review** - ML code reviewed like production code with attention to correctness and maintainability
- [ ] **Documentation** - Model architecture, training procedure, and deployment documented

## 12. Resource Management

- [ ] **GPU utilization** - GPU memory and compute monitored to avoid waste
- [ ] **Compute budgets** - Training compute budgets defined and tracked
- [ ] **Resource cleanup** - Training sessions release resources (close files, clear GPU memory) on completion
- [ ] **Distributed training** - Data parallelism or model parallelism used appropriately for large models/datasets
- [ ] **Spot instance usage** - Spot/preemptible instances used for cost savings with checkpointing
- [ ] **AutoML budgets** - AutoML search budgets constrained to avoid runaway costs
- [ ] **Storage optimization** - Model artifacts and datasets compressed to minimize storage costs

## Summary

AI/ML code requires specialized review focusing on reproducibility, fairness, deployment safety, and operational monitoring. These checks ensure ML systems are production-ready, maintainable, and trustworthy.

**Last Updated:** 2025-11-28
