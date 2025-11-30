# Python Docstrings and Documentation

## Table of Contents

- [Overview](#overview)
- [PEP 257 Docstring Conventions](#pep-257-docstring-conventions)
- [Docstring Styles Comparison](#docstring-styles-comparison)
- [Google Style Docstrings](#google-style-docstrings)
- [NumPy Style Docstrings](#numpy-style-docstrings)
- [Sphinx reStructuredText Style](#sphinx-restructuredtext-style)
- [Type Hints and Docstrings](#type-hints-and-docstrings)
- [Module-Level Docstrings](#module-level-docstrings)
- [Class Docstrings](#class-docstrings)
- [Function and Method Docstrings](#function-and-method-docstrings)
- [Sphinx Documentation Generator](#sphinx-documentation-generator)
- [Alternative Documentation Tools](#alternative-documentation-tools)
- [README.md Best Practices](#readmemd-best-practices)
- [CHANGELOG.md Best Practices](#changelogmd-best-practices)
- [Best Practices Summary](#best-practices-summary)
- [Official Documentation Links](#official-documentation-links)
- [Last Verified](#last-verified)

## Overview

This guide covers Python docstring conventions, documentation styles, and documentation generation tools based on official Python Enhancement Proposals (PEPs) and widely-adopted community standards.

## PEP 257 Docstring Conventions

**Official Source:** [PEP 257 - Docstring Conventions](https://peps.python.org/pep-0257/)

PEP 257 establishes the foundational standards for Python docstrings.

### What is a Docstring?

A docstring is a string literal that occurs as the first statement in a module, function, class, or method definition. Such a docstring becomes the `__doc__` special attribute of that object.

**Key Requirements:**

- All modules should normally have docstrings
- All functions and classes exported by a module should have docstrings
- Public methods (including `__init__`) should have docstrings
- Always use `"""triple double quotes"""` around docstrings
- Use `r"""raw triple double quotes"""` if you use backslashes

### One-Line Docstrings

One-liners are for really obvious cases. They should fit on one line.

**Example:**

```python
def kos_root():
    """Return the pathname of the KOS root directory."""
    global _kos_root
    if _kos_root:
        return _kos_root
    # ...
```

**Rules for One-Line Docstrings:**

- Triple quotes are used even though the string fits on one line
- The closing quotes are on the same line as the opening quotes
- There's no blank line either before or after the docstring
- The docstring is a phrase ending in a period
- It prescribes the function's effect as a command ("Do this", "Return that"), not as a description
- Don't write "Returns the pathname..." - use "Return the pathname..."
- The one-line docstring should NOT be a signature reiterating the function parameters

**Bad Example:**

```python
def function(a, b):
    """function(a, b) -> list"""  # Don't do this!
```

**Good Example:**

```python
def function(a, b):
    """Do X and return a list."""
```

### Multi-Line Docstrings

Multi-line docstrings consist of a summary line just like a one-line docstring, followed by a blank line, followed by a more elaborate description.

**Structure:**

1. Summary line (fits on one line)
2. Blank line
3. More elaborate description

**Example:**

```python
def complex(real=0.0, imag=0.0):
    """Form a complex number.

    Keyword arguments:
    real -- the real part (default 0.0)
    imag -- the imaginary part (default 0.0)
    """
    if imag == 0.0 and real == 0.0:
        return complex_zero
    # ...
```

**Guidelines:**

- The summary line may be on the same line as the opening quotes or on the next line
- The entire docstring is indented the same as the quotes at its first line
- Insert a blank line after all docstrings (one-line or multi-line) that document a class
- Place the closing quotes on a line by themselves (for multi-line docstrings)

### What to Document

**Functions and Methods:**

- Summarize behavior
- Document arguments, return value(s), side effects, exceptions raised
- Indicate optional arguments
- Document whether keyword arguments are part of the interface

**Classes:**

- Summarize behavior
- List public methods and instance variables
- If intended for subclassing, document the subclass interface separately
- Document the `__init__` method in its own docstring

**Modules:**

- List the classes, exceptions, and functions exported by the module
- Provide a one-line summary of each

**Scripts:**

- Docstring should be usable as a "usage" message
- Document the script's function and command line syntax

## Docstring Styles Comparison

Three dominant docstring styles have emerged in the Python community:

| Aspect | Google Style | NumPy Style | Sphinx reST |
| --- | --- | --- | --- |
| **Markup Language** | Plain text with indentation | Plain text with underlines | reStructuredText |
| **Readability (Simple)** | Excellent | Good | Poor |
| **Readability (Complex)** | Good | Excellent | Excellent |
| **Vertical Space** | Compact | Extended | Extended |
| **Learning Curve** | Easy | Moderate | Steep |
| **Sphinx Support** | Via napoleon extension | Via napoleon extension | Native |
| **Best For** | General purpose | Scientific computing | Professional documentation |
| **Community Adoption** | Very high | High (scientific Python) | Very high (formal docs) |

### When to Use Each Style

**Google Style:**

- General-purpose Python libraries
- Code readability is a priority
- Straightforward documentation needs
- Minimal tooling overhead

**NumPy Style:**

- Scientific, mathematical, or data analysis libraries
- Working with NumPy, SciPy, Pandas ecosystems
- Complex parameter relationships
- Multi-parameter functions with detailed specifications

**Sphinx reST Style:**

- Formal, publishable API documentation
- Large-scale projects with professional documentation portals
- Advanced formatting needs (cross-references, code blocks, tables)
- Existing Sphinx infrastructure

## Google Style Docstrings

Google style uses indentation to separate sections and follows a clean, horizontal structure.

### Google Function Example

```python
def calculate_total(items, tax_rate=0.08):
    """Calculate the total cost including tax.

    This function takes a list of item prices and applies a tax rate
    to compute the final total cost.

    Args:
        items (list): List of item prices as floats.
        tax_rate (float): Tax rate as a decimal (default: 0.08).

    Returns:
        float: The total cost including tax.

    Raises:
        ValueError: If items is empty or tax_rate is negative.

    Examples:
        >>> calculate_total([10.0, 20.0])
        32.4
    """
    if not items or tax_rate < 0:
        raise ValueError("Invalid inputs provided")
    subtotal = sum(items)
    return subtotal * (1 + tax_rate)
```

### Google Class Example

```python
class DataProcessor:
    """Process and transform raw data into usable formats.

    This class handles data validation, cleaning, and transformation
    operations for various data sources.

    Attributes:
        data (list): The raw input data.
        verbose (bool): Whether to print processing steps.

    Examples:
        >>> processor = DataProcessor([1, 2, 3])
        >>> processor.process()
    """

    def __init__(self, data, verbose=False):
        """Initialize the DataProcessor.

        Args:
            data (list): Raw data to process.
            verbose (bool): Enable verbose output (default: False).
        """
        self.data = data
        self.verbose = verbose

    def process(self):
        """Process the raw data.

        Returns:
            list: The processed data.

        Raises:
            ValueError: If data is empty or invalid.
        """
        if not self.data:
            raise ValueError("Data cannot be empty")
        return [x * 2 for x in self.data]
```

### Google Module Example

```python
"""Data processing utilities for financial calculations.

This module provides functions and classes for processing financial
transaction data, including validation, aggregation, and reporting.

Typical usage example:
    processor = TransactionProcessor('data.csv')
    summary = processor.generate_report()
"""
```

### Google Section Format

**Common Sections:**

- `Args:` - Function/method parameters
- `Returns:` - Return value description
- `Yields:` - For generator functions
- `Raises:` - Exceptions that may be raised
- `Attributes:` - Class attributes
- `Examples:` - Usage examples
- `Note:` - Additional notes
- `Warning:` - Important warnings

## NumPy Style Docstrings

NumPy style uses underlines to separate sections, creating clear visual boundaries.

### NumPy Function Example

```python
def compute_statistics(data, include_median=True):
    """Compute basic statistical measures for a dataset.

    Performs calculations of mean, standard deviation, and optionally
    the median value for the provided numerical data.

    Parameters
    ----------
    data : array-like
        Input data as a list or NumPy array of numerical values.
    include_median : bool, optional
        If True, includes median in output (default: True).

    Returns
    -------
    dict
        Dictionary containing 'mean', 'std', and optionally 'median' keys.

    Raises
    ------
    ValueError
        If data is empty or contains non-numeric values.
    TypeError
        If data is not array-like.

    See Also
    --------
    numpy.mean : NumPy mean function.
    numpy.std : NumPy standard deviation function.

    Notes
    -----
    This function uses NumPy for efficient computation. The standard
    deviation is computed using the population formula (ddof=0).

    Examples
    --------
    >>> compute_statistics([1, 2, 3, 4, 5])
    {'mean': 3.0, 'std': 1.414..., 'median': 3.0}

    >>> compute_statistics([10, 20, 30], include_median=False)
    {'mean': 20.0, 'std': 8.164...}
    """
    import numpy as np
    if not data:
        raise ValueError("Data cannot be empty")
    mean = np.mean(data)
    std = np.std(data)
    result = {'mean': mean, 'std': std}
    if include_median:
        result['median'] = np.median(data)
    return result
```

### NumPy Class Example

```python
class ImageAnalyzer:
    """Analyze image properties and extract features.

    This class provides methods for loading, processing, and analyzing
    digital images with various computational approaches.

    Parameters
    ----------
    filepath : str
        Path to the image file to analyze.

    Attributes
    ----------
    filepath : str
        Path to the image file.
    image_array : ndarray or None
        The loaded image as a NumPy array.
    processed : bool
        Whether the image has been processed.

    Methods
    -------
    load_image()
        Load the image from filepath.
    analyze()
        Perform analysis on the loaded image.

    Examples
    --------
    >>> analyzer = ImageAnalyzer('photo.jpg')
    >>> analyzer.load_image()
    >>> results = analyzer.analyze()
    """

    def __init__(self, filepath):
        self.filepath = filepath
        self.image_array = None
        self.processed = False

    def load_image(self):
        """Load the image from the specified filepath.

        Returns
        -------
        ndarray
            The loaded image as a NumPy array.

        Raises
        ------
        FileNotFoundError
            If the image file does not exist.
        """
        # Implementation here
        pass
```

### NumPy Module Example

```python
"""Financial data processing and analysis module.

Provides utilities for validating, cleaning, and analyzing
financial transaction datasets with support for multiple
file formats and data sources.

Classes
-------
TransactionProcessor
    Main class for processing financial data.
ReportGenerator
    Generate summary reports from processed data.

Functions
---------
validate_transaction
    Validate a single transaction record.
load_csv
    Load transaction data from CSV file.
"""
```

### NumPy Section Format

**Common Sections:**

- `Parameters` - Function/method parameters
- `Returns` - Return value description
- `Yields` - For generator functions
- `Raises` - Exceptions that may be raised
- `Attributes` - Class attributes
- `Methods` - Class methods (brief overview)
- `Examples` - Usage examples
- `See Also` - Related functions/classes
- `Notes` - Implementation notes
- `References` - Academic references

## Sphinx reStructuredText Style

Sphinx-style docstrings use field list syntax with reStructuredText markup.

### Sphinx Function Example

```python
def merge_datasets(dataset1, dataset2, on_key=None):
    """
    Merge two datasets using the specified key.

    :param dataset1: First dataset dictionary or DataFrame
    :type dataset1: dict or pd.DataFrame
    :param dataset2: Second dataset dictionary or DataFrame
    :type dataset2: dict or pd.DataFrame
    :param on_key: Column or key to merge on
    :type on_key: str or None
    :return: Merged dataset
    :rtype: dict or pd.DataFrame
    :raises KeyError: If on_key is not found in datasets
    :raises TypeError: If datasets are incompatible types

    Example usage:

    .. code-block:: python

        result = merge_datasets(data1, data2, on_key='id')
        print(result)

    .. note::
        This function performs an inner join by default.

    .. warning::
        Large datasets may consume significant memory.
    """
    if not on_key:
        raise ValueError("on_key parameter is required")
    # Merge logic here
    return {}
```

### Sphinx Class Example

```python
class DatabaseConnection:
    """
    Manage connections to a database system.

    Provides methods for connecting, querying, and disconnecting
    from various database backends with connection pooling support.

    :ivar host: Database server hostname
    :vartype host: str
    :ivar port: Database server port number
    :vartype port: int
    :ivar connected: Current connection status
    :vartype connected: bool
    """

    def __init__(self, host, port=5432):
        """
        Initialize database connection parameters.

        :param host: Hostname of database server
        :type host: str
        :param port: Port number (default 5432)
        :type port: int
        """
        self.host = host
        self.port = port
        self.connected = False
```

### Sphinx Module Example

```python
"""
Financial data processing and reporting module.

Provides comprehensive utilities for handling financial transaction
data with support for multiple formats and data validation.

:var DEFAULT_TIMEOUT: Default operation timeout in seconds
:vartype DEFAULT_TIMEOUT: int
:var SUPPORTED_FORMATS: List of supported file formats
:vartype SUPPORTED_FORMATS: list
"""

DEFAULT_TIMEOUT = 30
SUPPORTED_FORMATS = ['csv', 'json', 'excel']
```

### Field List Syntax

**Common Fields:**

- `:param name:` - Parameter description
- `:type name:` - Parameter type
- `:return:` - Return value description
- `:rtype:` - Return type
- `:raises Exception:` - Exception that may be raised
- `:ivar name:` - Instance variable
- `:vartype name:` - Instance variable type
- `:cvar name:` - Class variable

## Type Hints and Docstrings

Modern Python (3.5+) supports type hints, which should be preferred over documenting types in docstrings.

### Modern Approach: Type Hints + Docstrings

**Recommended Pattern:**

```python
def process_data(
    items: list[str],
    threshold: float = 0.5,
    verbose: bool = False
) -> dict[str, float]:
    """Process items and return statistics.

    Filters items based on threshold and computes statistics
    for the filtered dataset.

    Args:
        items: List of item identifiers to process.
        threshold: Minimum value for filtering (default: 0.5).
        verbose: Enable detailed logging (default: False).

    Returns:
        Dictionary mapping item IDs to computed values.

    Raises:
        ValueError: If items is empty or threshold is out of range.
    """
    if not items or not (0.0 <= threshold <= 1.0):
        raise ValueError("Invalid input parameters")
    return {item: threshold for item in items}
```

**Benefits:**

- Type information is checked by static analysis tools (mypy, pyright)
- IDEs provide better autocomplete and error detection
- Docstrings focus on behavior and purpose, not type details
- No duplication between type hints and docstring type annotations

### When Type Hints are Insufficient

For complex types, you may need docstring clarification:

```python
def transform_matrix(
    data: list[list[float]],
    mode: str = 'normalize'
) -> list[list[float]]:
    """Transform a 2D matrix using the specified mode.

    Args:
        data: 2D matrix as a list of lists. Each inner list represents
            a row. All rows must have the same length.
        mode: Transformation mode. Valid options are 'normalize',
            'standardize', or 'scale'. Default is 'normalize'.

    Returns:
        Transformed 2D matrix with the same dimensions as input.

    Raises:
        ValueError: If mode is invalid or matrix rows have different lengths.
    """
    # Implementation
    pass
```

## Module-Level Docstrings

Module docstrings appear at the top of a Python file and describe the module's purpose.

### Module Template

```python
"""Brief one-line description of the module.

More detailed description explaining what the module does,
its primary use cases, and any important context.

Typical usage example:

    from mymodule import MyClass
    obj = MyClass()
    result = obj.process()

Classes:
    ClassName: Brief description.
    AnotherClass: Brief description.

Functions:
    function_name: Brief description.
    another_function: Brief description.

Exceptions:
    CustomError: Brief description.

Constants:
    CONSTANT_NAME: Brief description.
"""
# Module code follows
```

### Example

```python
"""Financial transaction processing and analysis.

This module provides utilities for loading, validating, cleaning, and
analyzing financial transaction data from multiple sources including
CSV files, databases, and API endpoints.

The primary workflow involves:
1. Loading data using TransactionLoader
2. Validating with TransactionValidator
3. Processing with TransactionProcessor
4. Generating reports with ReportGenerator

Typical usage example:

    loader = TransactionLoader('transactions.csv')
    data = loader.load()
    validator = TransactionValidator()
    if validator.validate(data):
        processor = TransactionProcessor(data)
        summary = processor.generate_summary()
"""
```

## Class Docstrings

Class docstrings describe the class purpose, attributes, and methods.

### Class Template

```python
class ClassName:
    """Brief one-line description of the class.

    More detailed description of the class behavior, use cases,
    and important characteristics.

    Attributes:
        attr1: Description of first attribute.
        attr2: Description of second attribute.

    Methods:
        method1: Brief description of method.
        method2: Brief description of method.

    Examples:
        >>> obj = ClassName(arg1, arg2)
        >>> result = obj.method1()
    """
```

### Documenting `__init__`

The `__init__` method should have its own docstring:

```python
class Customer:
    """Represent a customer account.

    Manages customer information, transaction history, and
    account status for e-commerce operations.

    Attributes:
        customer_id (str): Unique customer identifier.
        email (str): Customer email address.
        created_at (datetime): Account creation timestamp.
        active (bool): Whether the account is active.
    """

    def __init__(self, customer_id: str, email: str):
        """Initialize a new customer account.

        Args:
            customer_id: Unique identifier for the customer.
            email: Customer's email address.

        Raises:
            ValueError: If customer_id or email is invalid.
        """
        if not customer_id or not email:
            raise ValueError("Customer ID and email are required")
        self.customer_id = customer_id
        self.email = email
        from datetime import datetime
        self.created_at = datetime.now()
        self.active = True
```

## Function and Method Docstrings

### Function Template

```python
def function_name(param1, param2, param3=None):
    """Brief one-line description.

    More detailed description of what the function does,
    including algorithm details if relevant.

    Args:
        param1: Description of first parameter.
        param2: Description of second parameter.
        param3: Description of optional parameter (default: None).

    Returns:
        Description of return value.

    Raises:
        ExceptionType: When this exception is raised.

    Examples:
        >>> function_name(val1, val2)
        expected_result
    """
```

### Generator Functions

For generators, use `Yields` instead of `Returns`:

```python
def generate_numbers(start: int, end: int):
    """Generate numbers in the specified range.

    Args:
        start: Starting number (inclusive).
        end: Ending number (exclusive).

    Yields:
        int: The next number in the sequence.

    Examples:
        >>> list(generate_numbers(1, 5))
        [1, 2, 3, 4]
    """
    for i in range(start, end):
        yield i
```

## Sphinx Documentation Generator

**Official Documentation:** [https://www.sphinx-doc.org/](https://www.sphinx-doc.org/)

Sphinx is the de facto standard for Python documentation generation, used for official Python documentation and most major Python projects.

### Installation

```python
pip install sphinx
```

### Getting Started with Sphinx

**1. Run sphinx-quickstart:**

```python
sphinx-quickstart
```

This creates:

- `conf.py` - Configuration file
- `index.rst` - Root document
- `Makefile` - Build automation (Unix/Linux/macOS)
- `make.bat` - Build automation (Windows)

**2. Configure `conf.py`:**

```python
# conf.py

# Project information
project = 'My Project'
copyright = '2024, Your Name'
author = 'Your Name'
release = '1.0.0'

# Extensions
extensions = [
    'sphinx.ext.autodoc',      # Auto-generate docs from docstrings
    'sphinx.ext.napoleon',     # Support Google/NumPy style docstrings
    'sphinx.ext.viewcode',     # Add source code links
    'sphinx.ext.intersphinx',  # Link to other projects' docs
]

# Napoleon settings (for Google/NumPy style)
napoleon_google_docstring = True
napoleon_numpy_docstring = True
napoleon_include_init_with_doc = False
napoleon_include_private_with_doc = False
napoleon_include_special_with_doc = True
napoleon_use_param = True
napoleon_use_rtype = True

# Theme
html_theme = 'sphinx_rtd_theme'  # ReadTheDocs theme

# Intersphinx mapping (link to Python docs)
intersphinx_mapping = {
    'python': ('https://docs.python.org/3', None),
}
```

**3. Build Documentation:**

```python
make html
```

Or on Windows:

```python
make.bat html
```

Output will be in `_build/html/index.html`.

### Using Autodoc

Autodoc automatically generates documentation from your Python modules.

**Example `index.rst`:**

```rst

Welcome to My Project
=====================

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   api

API Reference
=============

.. automodule:: mypackage.mymodule
   :members:
   :undoc-members:
   :show-inheritance:
```python

**Autodoc Directives:**

- `.. automodule::` - Document a module
- `.. autoclass::` - Document a class
- `.. autofunction::` - Document a function
- `.. automethod::` - Document a method

**Options:**

- `:members:` - Include all members
- `:undoc-members:` - Include members without docstrings
- `:show-inheritance:` - Show base classes
- `:private-members:` - Include private members (starting with `_`)
- `:special-members:` - Include special members (like `__init__`)

### Live Preview with Autobuild

Install sphinx-autobuild for automatic rebuilding:

```

pip install sphinx-autobuild

```python

Run live server:

```

sphinx-autobuild source build/html

```python

Opens browser with live-reloading documentation.

### Themes

**Popular Themes:**

- `sphinx_rtd_theme` - ReadTheDocs theme (most popular)
- `alabaster` - Sphinx default theme
- `pydata_sphinx_theme` - PyData community theme
- `furo` - Modern, clean theme

**Install and configure:**

```bash
pip install sphinx-rtd-theme
```

```python
# conf.py
html_theme = 'sphinx_rtd_theme'
```

### Hosting on ReadTheDocs

**ReadTheDocs** ([https://readthedocs.org/](https://readthedocs.org/)) provides free hosting for Sphinx documentation.

**Setup:**

1. Create `.readthedocs.yaml` in repository root:

```yaml

version: 2

build:
  os: ubuntu-22.04
  tools:
    python: "3.11"

sphinx:
  configuration: docs/conf.py

python:
  install:
    - requirements: docs/requirements.txt
```

1. Create `docs/requirements.txt`:

```python
sphinx>=7.0
sphinx-rtd-theme>=2.0
```

1. Connect repository to ReadTheDocs at [https://readthedocs.org/dashboard/](https://readthedocs.org/dashboard/)

2. Documentation automatically builds on every commit

**Features:**

- Automatic builds on commit
- Multiple version support
- Search functionality
- Custom domains
- PDF downloads

## Alternative Documentation Tools

### MkDocs

**Website:** [https://www.mkdocs.org/](https://www.mkdocs.org/)

Markdown-based documentation generator.

**Installation:**

```python
pip install mkdocs
```

**Quick Start:**

```python
mkdocs new my-project
cd my-project
mkdocs serve
```

**Features:**

- Pure Markdown (no reST)
- Fast setup and build times
- Live preview with hot reloading
- Material theme (Material for MkDocs)

**Best For:**

- Project wikis
- Simple documentation
- Markdown preference over reST
- Quick setup

**GitHub Pages Deployment:**

```python
mkdocs gh-deploy
```

### pdoc

**Website:** [https://pdoc.dev/](https://pdoc.dev/)

Automatic API documentation with zero configuration.

**Installation:**

```python
pip install pdoc
```

**Usage:**

```python
pdoc your_module
```

**Features:**

- Zero configuration required
- Automatic API documentation from docstrings
- Excellent type hint support
- Live-reloading server
- Lightweight

**Best For:**

- Auto-generated API documentation
- Small to medium libraries
- Type-annotated code
- Minimal setup requirements

### pydoc

#### Built-in Python Tool

Part of Python standard library, no installation needed.

**Usage:**

```python
python -m pydoc module_name
python -m pydoc -w module_name  # Generate HTML
python -m pydoc -p 1234         # Start HTTP server
```

**Features:**

- No external dependencies
- Quick documentation viewing
- Text or HTML output

**Best For:**

- Quick module documentation viewing
- No external tools available
- Built-in help systems

### Comparison Summary

| Tool | Setup | Markup | Auto API Docs | Output | Best For |
| --- | --- | --- | --- | --- | --- |
| **Sphinx** | Medium | reST/Markdown | Yes (autodoc) | HTML, PDF, ePub | Professional docs, large projects |
| **MkDocs** | Easy | Markdown | Limited | HTML | Wikis, simple docs, quick setup |
| **pdoc** | Very Easy | From code | Yes | HTML, text | Auto API docs, type hints |
| **pydoc** | None | From code | Yes | HTML, text | Quick viewing, built-in help |

## README.md Best Practices

A well-structured README is the entry point to your project.

### README Template

````markdown
# Project Title

**Short tagline or one-sentence description.**

[![Build Status](https://img.shields.io/github/actions/workflow/status/username/project/ci.yml?branch=main)](https://github.com/username/project/actions)
[![Coverage](https://img.shields.io/coveralls/github/username/project/main.svg)](https://coveralls.io/github/username/project)
[![PyPI version](https://img.shields.io/pypi/v/package-name.svg)](https://pypi.org/project/package-name/)
[![License](https://img.shields.io/github/license/username/project.svg)](LICENSE)

## Description

Brief description of what your package does, who it's for, and what problems it solves.

Example: A command-line tool that automates data cleaning for CSV files with
built-in validation and reporting features.

## Features

- Easy CSV parsing with automatic type detection
- Comprehensive data validation rules
- Detailed logging and error reporting
- Export to multiple formats (JSON, Excel, Parquet)

## Installation

### From PyPI

```bash
pip install package-name
```

### From Source

```bash
git clone <https://github.com/username/project.git>
cd project
pip install -e .
```

### Requirements

- Python 3.8+
- pandas >= 1.5.0
- numpy >= 1.24.0

## Quick Start

```python
import package_name

# Basic usage
processor = package_name.DataProcessor('input.csv')
result = processor.clean()
result.save('output.csv')
```

### CLI Usage

```bash
package-name input.csv --output cleaned.csv --verbose
```

## Documentation

Full documentation is available at [https://package-name.readthedocs.io/](https://package-name.readthedocs.io/)

## Examples

### Example 1: Basic Data Cleaning

```python
from package_name import DataProcessor

processor = DataProcessor('data.csv')
processor.remove_duplicates()
processor.fill_missing_values(strategy='mean')
processor.save('clean_data.csv')

```

### Example 2: Custom Validation

```python
from package_name import DataValidator

validator = DataValidator()
validator.add_rule('age', min_value=0, max_value=120)
validator.add_rule('email', pattern=r'^[\w\.-]+@[\w\.-]+\.\w+$')

if validator.validate(data):
    print("Data is valid!")
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Ways to contribute:

- Report bugs via [Issues](https://github.com/username/project/issues)
- Submit feature requests
- Improve documentation
- Submit pull requests

## Testing

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run tests with coverage
pytest --cov=package_name
```

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Citation

If you use this package in your research, please cite:

```bibtex

@software{package_name,
  author = {Your Name},
  title = {Package Name},
  year = {2024},
  url = {https://github.com/username/project}
}
```

## Acknowledgments

- Thanks to contributors (link to contributors page)
- Inspired by [similar-project](https://github.com/other/project)

## Contact

For support or questions:

- Open an [Issue](https://github.com/username/project/issues)
- Email: <maintainer@domain.com>
- Discord: [Project Server](https://discord.gg/invite-link)

````

### Essential Sections

**Must Have:**

1. Project title and description
2. Installation instructions
3. Basic usage examples
4. License

**Should Have:**

1. Features list
2. Requirements/dependencies
3. Contributing guidelines
4. Contact/support information

**Nice to Have:**

1. Badges (build status, coverage, version, license)
2. Documentation links
3. Screenshots/demos
4. Citation information
5. Acknowledgments

### Badge Examples

```markdown
<!-- Build Status -->
[![Build](https://img.shields.io/github/actions/workflow/status/user/repo/ci.yml)](https://github.com/user/repo/actions)

<!-- Coverage -->
[![Coverage](https://img.shields.io/codecov/c/github/user/repo)](https://codecov.io/gh/user/repo)

<!-- PyPI Version -->
[![PyPI](https://img.shields.io/pypi/v/package-name)](https://pypi.org/project/package-name/)

<!-- Python Versions -->
[![Python](https://img.shields.io/pypi/pyversions/package-name)](https://pypi.org/project/package-name/)

<!-- License -->
[![License](https://img.shields.io/github/license/user/repo)](LICENSE)

<!-- Downloads -->
[![Downloads](https://img.shields.io/pypi/dm/package-name)](https://pypi.org/project/package-name/)

```

Badge service: [https://shields.io/](https://shields.io/)

## CHANGELOG.md Best Practices

**Source:** [Keep a Changelog](https://keepachangelog.com/)

A changelog is a curated, chronologically ordered list of notable changes for each version.

### Changelog Template

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- New feature X for improved performance

### Changed

- Updated dependency Y to version 2.0

### Deprecated

- Feature Z will be removed in version 3.0

## [1.2.0] - 2024-01-15

### Added

- Support for CSV export format
- New validation rules for email addresses
- CLI option `--strict` for strict validation mode

### Changed

- Improved error messages for validation failures
- Updated pandas dependency to 2.0.0

### Fixed

- Bug in date parsing for non-US locales
- Memory leak in large file processing

### Security

- Fixed SQL injection vulnerability in query builder

## [1.1.0] - 2023-12-01

### Added

- Batch processing support for multiple files
- Progress bar for long-running operations

### Deprecated

- `process_file()` function - use `process()` instead

## [1.0.0] - 2023-10-15

### Added

- Initial release
- CSV data cleaning functionality
- Basic validation rules
- Command-line interface

[Unreleased]: https://github.com/user/repo/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/user/repo/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/user/repo/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/user/repo/releases/tag/v1.0.0

```

### Change Types

- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Now removed features
- **Fixed** - Bug fixes
- **Security** - Security vulnerability fixes

### Best Practices

**Do:**

- Keep an `Unreleased` section at the top
- List changes for humans, not machines
- Group the same types of changes
- Make versions and sections linkable
- Put the latest version first
- Display the release date of each version
- Follow Semantic Versioning

**Don't:**

- Use commit log diffs as changelogs (too noisy)
- Ignore deprecations (warn users before breaking changes)
- Use confusing date formats (use YYYY-MM-DD ISO 8601)
- Be inconsistent (document all notable changes)

### Semantic Versioning Alignment

Given a version number MAJOR.MINOR.PATCH (e.g., 1.2.3):

- **MAJOR** - Incompatible API changes (breaking changes)
- **MINOR** - Backwards-compatible new functionality
- **PATCH** - Backwards-compatible bug fixes

Align changelog sections with version bumps:

- `Removed` or breaking `Changed` → MAJOR version bump
- `Added` → MINOR version bump
- `Fixed` → PATCH version bump

## Best Practices Summary

### Docstring Best Practices

1. **Always write docstrings** for public modules, classes, functions, and methods
2. **Use triple double quotes** (`"""`) for all docstrings
3. **Start with a summary line** that fits on one line
4. **Follow PEP 257** for basic structure
5. **Choose one style** (Google, NumPy, or Sphinx) and use it consistently
6. **Use type hints** instead of documenting types in docstrings
7. **Include examples** in docstrings where helpful
8. **Explain "why" not just "what"** - the code shows what, docstrings explain why
9. **Keep docstrings up-to-date** when code changes
10. **Use imperative mood** for function descriptions ("Return the value", not "Returns the value")

### Documentation Generation Best Practices

1. **Use Sphinx** for comprehensive documentation needs
2. **Auto-generate API docs** with autodoc extension
3. **Enable napoleon** for Google/NumPy style support
4. **Host on ReadTheDocs** for automatic building and versioning
5. **Include a comprehensive README.md** with installation and quick start
6. **Maintain a CHANGELOG.md** following Keep a Changelog format
7. **Add badges** to README for build status, coverage, and version
8. **Write tutorials and guides** in addition to API reference
9. **Test code examples** in documentation
10. **Version your documentation** alongside code releases

### Style Selection Guide

**Choose Google style for:**

- General-purpose libraries
- Internal projects
- Code-first documentation approach

**Choose NumPy style for:**

- Scientific/mathematical libraries
- Projects in NumPy/SciPy ecosystem
- Complex parameter specifications

**Choose Sphinx reST for:**

- Maximum documentation control
- Complex cross-referencing needs
- Traditional Sphinx-first approach

## Official Documentation Links

- **PEP 257 - Docstring Conventions**: [https://peps.python.org/pep-0257/](https://peps.python.org/pep-0257/)
- **Sphinx Documentation**: [https://www.sphinx-doc.org/](https://www.sphinx-doc.org/)
- **Sphinx Napoleon Extension**: [https://www.sphinx-doc.org/en/master/usage/extensions/napoleon.html](https://www.sphinx-doc.org/en/master/usage/extensions/napoleon.html)
- **Google Python Style Guide**: [https://google.github.io/styleguide/pyguide.html](https://google.github.io/styleguide/pyguide.html)
- **NumPy Docstring Standard**: [https://numpydoc.readthedocs.io/](https://numpydoc.readthedocs.io/)
- **Keep a Changelog**: [https://keepachangelog.com/](https://keepachangelog.com/)
- **Semantic Versioning**: [https://semver.org/](https://semver.org/)
- **ReadTheDocs**: [https://readthedocs.org/](https://readthedocs.org/)
- **MkDocs**: [https://www.mkdocs.org/](https://www.mkdocs.org/)
- **pdoc**: [https://pdoc.dev/](https://pdoc.dev/)

## Last Verified

**Date:** 2024-11-17

**Sources:**

- PEP 257 (Last modified: 2024-04-17)
- Sphinx Documentation (master branch)
- Keep a Changelog (v1.1.0)
- Perplexity search results (2024 best practices)

**Tool Versions:**

- Sphinx: 7.0+
- Python: 3.8+
- sphinx-rtd-theme: 2.0+
