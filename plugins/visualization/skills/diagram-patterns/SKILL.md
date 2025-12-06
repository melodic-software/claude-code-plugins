---
name: diagram-patterns
description: Decision guidance for selecting the right diagram type and tool. Provides patterns for common visualization scenarios, tool comparison, and best practices.
allowed-tools: Read, Glob, Grep, Skill
---

# Diagram Selection & Patterns

## Overview

This skill helps you choose the right diagram type and tool for your visualization needs. Use this when you need to decide:

1. **Which diagram type** best represents your information
2. **Which tool** (Mermaid or PlantUML) to use
3. **How to structure** the diagram for clarity

---

## Diagram Type Decision Tree

### What are you trying to visualize?

```text
START
  |
  +-- Interactions over time? --> SEQUENCE DIAGRAM
  |
  +-- Object/class structure? --> CLASS DIAGRAM
  |
  +-- Database schema? --> ER DIAGRAM
  |
  +-- State transitions? --> STATE DIAGRAM
  |
  +-- Process/workflow? --> FLOWCHART or ACTIVITY DIAGRAM
  |
  +-- System architecture?
  |     |
  |     +-- High-level context? --> C4 CONTEXT
  |     +-- Containers/services? --> C4 CONTAINER or COMPONENT
  |     +-- Infrastructure? --> DEPLOYMENT DIAGRAM
  |
  +-- Project timeline? --> GANTT CHART
  |
  +-- Git branching? --> GIT GRAPH (Mermaid only)
  |
  +-- Hierarchical ideas? --> MINDMAP (PlantUML only)
  |
  +-- Data structure? --> JSON DIAGRAM (PlantUML only)
```

---

## Tool Selection Guide

### Quick Decision Matrix

| Need | Recommended Tool | Reason |
| --- | --- | --- |
| GitHub/GitLab rendering | **Mermaid** | Native support |
| Complex C4 models | **PlantUML** | Mature, better rendering |
| Simple sequence/class | **Mermaid** | Simpler syntax |
| MindMaps | **PlantUML** | Only option |
| JSON visualization | **PlantUML** | Only option |
| GitGraph | **Mermaid** | Only option |
| ER diagrams | **Mermaid** | Better default rendering |
| State diagrams | **Mermaid** | Cleaner output |
| Maximum customization | **PlantUML** | More styling options |
| Zero setup | **Mermaid** | Browser-based |
| Enterprise architecture | **PlantUML** | Better ArchiMate, C4 |

### Detailed Comparison

| Feature | Mermaid | PlantUML |
| --- | --- | --- |
| **Setup** | None (browser) | Java + GraphViz |
| **Markdown integration** | Native (GitHub, GitLab) | Requires image embedding |
| **Learning curve** | Gentle | Steeper |
| **Customization** | Limited | Extensive |
| **C4 support** | Experimental | Mature |
| **Diagram types** | ~10 | 15+ |
| **JSON/MindMap** | No | Yes |
| **GitGraph** | Yes | No |
| **Rendering quality** | Good | Good |
| **Version control** | Inline in Markdown | Separate .puml files |

### When to Choose Mermaid

- Documentation that lives in GitHub/GitLab repos
- Quick diagrams that need no setup
- Teams with mixed technical backgrounds
- Diagrams that need to stay in sync with docs
- Simple to moderately complex diagrams
- ER and state diagrams (better default styling)

### When to Choose PlantUML

- Complex enterprise architecture (C4, ArchiMate)
- Maximum control over appearance
- Specialized diagrams (MindMap, JSON, WBS)
- Established PlantUML workflow
- Need for sprites/icons
- Complex class diagrams with many relationships

---

## Pattern Library

### Sequence Diagram Patterns

#### API Request/Response

```mermaid
sequenceDiagram
    actor User
    participant FE as Frontend
    participant API as API Server
    participant DB as Database

    User->>FE: Action
    FE->>+API: Request
    API->>+DB: Query
    DB-->>-API: Data
    API-->>-FE: Response
    FE-->>User: Update UI
```

#### Authentication Flow

```mermaid
sequenceDiagram
    actor User
    participant App as Application
    participant Auth as Auth Service
    participant Token as Token Store

    User->>App: Login request
    App->>Auth: Validate credentials
    alt Valid
        Auth->>Token: Generate token
        Token-->>Auth: JWT
        Auth-->>App: Success + JWT
        App-->>User: Redirect to dashboard
    else Invalid
        Auth-->>App: 401 Unauthorized
        App-->>User: Show error
    end
```

#### Async Processing

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant Queue
    participant Worker

    Client->>API: Submit job
    API->>Queue: Enqueue task
    API-->>Client: 202 Accepted + job ID

    Worker->>Queue: Poll for tasks
    Queue-->>Worker: Task data
    Worker->>Worker: Process

    Client->>API: Check status (polling)
    API-->>Client: Status: processing

    Worker->>API: Report completion
    Client->>API: Check status
    API-->>Client: Status: complete + result
```

---

### Class Diagram Patterns

#### Domain Model

```mermaid
classDiagram
    class Entity {
        <<abstract>>
        +UUID id
        +DateTime createdAt
        +DateTime updatedAt
    }

    class User {
        +String email
        +String name
        +authenticate()
    }

    class Order {
        +OrderStatus status
        +Money total
        +submit()
        +cancel()
    }

    class OrderItem {
        +int quantity
        +Money price
    }

    Entity <|-- User
    Entity <|-- Order
    User "1" --> "*" Order : places
    Order "1" *-- "*" OrderItem : contains
```

#### Repository Pattern

```mermaid
classDiagram
    class IRepository~T~ {
        <<interface>>
        +findById(id) T
        +findAll() List~T~
        +save(entity) T
        +delete(id) void
    }

    class UserRepository {
        +findByEmail(email) User
    }

    class InMemoryUserRepository {
        -Map~UUID,User~ store
    }

    class PostgresUserRepository {
        -DataSource ds
    }

    IRepository~T~ <|.. UserRepository
    UserRepository <|-- InMemoryUserRepository
    UserRepository <|-- PostgresUserRepository
```

#### Service Layer

```mermaid
classDiagram
    class OrderService {
        -OrderRepository orderRepo
        -PaymentService paymentService
        -InventoryService inventoryService
        +createOrder(request) Order
        +cancelOrder(orderId) void
    }

    class PaymentService {
        -PaymentGateway gateway
        +processPayment(order) PaymentResult
        +refund(paymentId) void
    }

    class InventoryService {
        -InventoryRepository inventoryRepo
        +reserve(items) Reservation
        +release(reservationId) void
    }

    OrderService --> PaymentService
    OrderService --> InventoryService
```

---

### ER Diagram Patterns

#### Blog Schema

```mermaid
erDiagram
    USER {
        uuid id PK
        string email UK
        string password_hash
        string name
        timestamp created_at
    }

    POST {
        uuid id PK
        uuid author_id FK
        string title
        text content
        enum status
        timestamp published_at
    }

    COMMENT {
        uuid id PK
        uuid post_id FK
        uuid user_id FK
        text content
        timestamp created_at
    }

    TAG {
        uuid id PK
        string name UK
    }

    POST_TAG {
        uuid post_id PK,FK
        uuid tag_id PK,FK
    }

    USER ||--o{ POST : writes
    USER ||--o{ COMMENT : writes
    POST ||--o{ COMMENT : has
    POST ||--o{ POST_TAG : has
    TAG ||--o{ POST_TAG : has
```

#### E-Commerce Schema

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ ORDER_ITEM : contains
    PRODUCT ||--o{ ORDER_ITEM : "ordered in"
    PRODUCT }|--|| CATEGORY : "belongs to"
    CUSTOMER ||--o{ ADDRESS : has
    ORDER ||--|| ADDRESS : "ships to"
    ORDER ||--o| PAYMENT : "paid by"

    CUSTOMER {
        uuid id PK
        string email UK
        string name
    }

    ORDER {
        uuid id PK
        uuid customer_id FK
        uuid shipping_address_id FK
        enum status
        decimal total
    }

    ORDER_ITEM {
        uuid order_id PK,FK
        uuid product_id PK,FK
        int quantity
        decimal unit_price
    }

    PRODUCT {
        uuid id PK
        string sku UK
        string name
        decimal price
        int stock
    }
```

---

### State Diagram Patterns

#### Order Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Draft

    Draft --> Submitted : submit
    Submitted --> Confirmed : confirm
    Submitted --> Cancelled : cancel

    Confirmed --> Processing : process
    Processing --> Shipped : ship
    Processing --> Cancelled : cancel

    Shipped --> Delivered : deliver
    Shipped --> Returned : return

    Delivered --> [*]
    Returned --> Refunded : refund
    Refunded --> [*]
    Cancelled --> [*]
```

#### Authentication State

```mermaid
stateDiagram-v2
    [*] --> Anonymous

    Anonymous --> Authenticating : login
    Authenticating --> Authenticated : success
    Authenticating --> Anonymous : failure

    Authenticated --> Anonymous : logout
    Authenticated --> TokenRefresh : token_expiring
    TokenRefresh --> Authenticated : refresh_success
    TokenRefresh --> Anonymous : refresh_failure
```

---

### Flowchart Patterns

#### Decision Tree

```mermaid
flowchart TD
    Start([Start]) --> Q1{Is it urgent?}
    Q1 -->|Yes| Q2{Is it important?}
    Q1 -->|No| Q3{Is it important?}

    Q2 -->|Yes| Do[Do it now]
    Q2 -->|No| Delegate[Delegate it]

    Q3 -->|Yes| Schedule[Schedule it]
    Q3 -->|No| Eliminate[Eliminate it]

    Do --> End([End])
    Delegate --> End
    Schedule --> End
    Eliminate --> End
```

#### Error Handling Flow

```mermaid
flowchart TD
    Request([Request]) --> Validate{Valid?}

    Validate -->|Yes| Process[Process Request]
    Validate -->|No| ValidationError[Return 400]

    Process --> ExternalCall[Call External API]
    ExternalCall --> Success{Success?}

    Success -->|Yes| Transform[Transform Response]
    Success -->|No| Retry{Retries left?}

    Retry -->|Yes| Wait[Wait & Retry]
    Wait --> ExternalCall
    Retry -->|No| ServiceError[Return 503]

    Transform --> Cache[Cache Result]
    Cache --> Response([Return 200])

    ValidationError --> End([End])
    ServiceError --> End
    Response --> End
```

---

### C4 Patterns

#### System Context (Mermaid - Experimental)

```mermaid
C4Context
    title System Context - E-Commerce Platform

    Person(customer, "Customer", "Online shopper")
    Person(admin, "Admin", "Store administrator")

    System(ecommerce, "E-Commerce Platform", "Main shopping platform")

    System_Ext(payment, "Payment Gateway", "Stripe")
    System_Ext(shipping, "Shipping Provider", "FedEx API")
    System_Ext(email, "Email Service", "SendGrid")

    Rel(customer, ecommerce, "Browses, purchases")
    Rel(admin, ecommerce, "Manages products, orders")
    Rel(ecommerce, payment, "Processes payments")
    Rel(ecommerce, shipping, "Creates shipments")
    Rel(ecommerce, email, "Sends notifications")
```

#### Container Diagram (PlantUML Recommended)

```text
@startuml
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Container.puml

title Container Diagram - E-Commerce Platform

Person(customer, "Customer", "Online shopper")

System_Boundary(platform, "E-Commerce Platform") {
    Container(web, "Web Application", "React", "Customer-facing storefront")
    Container(admin, "Admin Panel", "React", "Back-office management")
    Container(api, "API Gateway", "Node.js", "API routing and auth")
    Container(catalog, "Catalog Service", "Go", "Product management")
    Container(orders, "Order Service", "Go", "Order processing")
    Container(cart, "Cart Service", "Go", "Shopping cart")
    ContainerDb(db, "Database", "PostgreSQL", "Persistent storage")
    Container(cache, "Cache", "Redis", "Session and product cache")
    Container(queue, "Message Queue", "RabbitMQ", "Async processing")
}

Rel(customer, web, "Uses", "HTTPS")
Rel(web, api, "API calls", "REST")
Rel(admin, api, "API calls", "REST")
Rel(api, catalog, "Routes to")
Rel(api, orders, "Routes to")
Rel(api, cart, "Routes to")
Rel(catalog, db, "Reads/Writes")
Rel(orders, db, "Reads/Writes")
Rel(cart, cache, "Reads/Writes")
Rel(orders, queue, "Publishes")
@enduml
```

---

## Best Practices

### General Guidelines

1. **Keep it simple**: Start with the minimum needed to convey the concept
2. **Use consistent naming**: Same entity = same name across diagrams
3. **Label relationships**: Arrows without labels are ambiguous
4. **Use direction thoughtfully**: TD for hierarchies, LR for flows
5. **Group related elements**: Use subgraphs/packages to organize
6. **Add legends**: For complex diagrams with many relationship types

### Diagram-Specific Tips

#### Sequence Diagrams

- Order participants left-to-right by typical flow
- Use activation bars to show processing time
- Group related interactions with boxes (alt, loop, opt)
- Add autonumber for complex sequences

#### Class Diagrams

- Show only relevant attributes/methods
- Use stereotypes to clarify roles (`<<Entity>>`, `<<Service>>`)
- Keep inheritance hierarchies shallow (2-3 levels)
- Position parent classes above children

#### ER Diagrams

- Always show primary keys (PK)
- Mark foreign keys (FK)
- Use relationship verbs ("places", "contains")
- Show cardinality on all relationships

#### State Diagrams

- Start from [*] initial state
- End at [*] terminal state
- Label all transitions with events
- Use composite states for complex machines

#### Flowcharts

- Use consistent shapes (rectangles for actions, diamonds for decisions)
- Flow generally top-to-bottom or left-to-right
- Avoid crossing lines when possible
- Label decision branches clearly (Yes/No, True/False)

---

## Anti-Patterns to Avoid

### Too Much Detail

- **Problem**: Diagram is cluttered and hard to read
- **Solution**: Create multiple focused diagrams at different abstraction levels

### Missing Context

- **Problem**: Diagram shows internal structure but not external interactions
- **Solution**: Start with context diagram, then zoom in

### Inconsistent Abstraction

- **Problem**: Mixing high-level and low-level concepts
- **Solution**: Keep consistent abstraction level per diagram

### Unlabeled Relationships

- **Problem**: Arrows connect things but meaning is unclear
- **Solution**: Always label with verb phrases (e.g., "uses", "contains", "sends")

### Missing Legend

- **Problem**: Custom shapes/colors without explanation
- **Solution**: Add legend for non-standard notation

---

## Quick Reference: Choosing Diagram Type

| Question | If Yes, Use |
| -------- | ----------- |
| Showing message flow between systems? | Sequence |
| Modeling OOP classes and relationships? | Class |
| Documenting database tables? | ER |
| Showing valid state transitions? | State |
| Depicting a process or algorithm? | Flowchart |
| High-level system overview? | C4 Context |
| Service/container architecture? | C4 Container |
| Timeline or schedule? | Gantt |
| Git branching strategy? | Git Graph |
| Brainstorming hierarchy? | MindMap |

---

## Delegation

For detailed syntax reference:

- **Mermaid syntax**: Invoke `visualization:mermaid-syntax` skill
- **PlantUML syntax**: Invoke `visualization:plantuml-syntax` skill

---

**Last Updated:** 2025-12-06
