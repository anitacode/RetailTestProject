# Retail Inventory Tracking System

## Project Overview

This project simulates a simplified retail inventory-tracking system. You are provided with:

- A set of **Stores**
- A set of **Brands**
- A set of **Products**
- A large CSV file containing **1,000,000 tracking events**
- A basic importer that reads the CSV and creates `TrackingEvent` records

Your goal is to improve the system, modify one of its key features, and then add a new feature.

You are encouraged to:
- Refactor existing code
- Introduce new endpoints or views
- Improve performance, clarity, and maintainability

There is no single "correct" solution — but there are many poor ones. We want to see how **you** design and implement a real-world improvement inside a Rails application.

## Setup

This app is a standard Rails 7.1 / Ruby 3.4 project backed by PostgreSQL.

### Prerequisites

- **Ruby**: `3.4.11`
- **Rails**: `~> 7.1.6`
- **PostgreSQL**: 13+ recommended

You can use **rbenv**, **rvm**, or **asdf** to install the correct Ruby version.

#### Installing Ruby with rbenv
```bash
# Install Ruby 3.4.11
rbenv install 3.4.11

# Set it locally for this project
rbenv local 3.4.11
```

### Installation
```bash
# Install dependencies
bundle install

# Set up the database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

### Running tests

Configure `DB_USER`, `DB_PASSWORD`, `DB_HOST`, and `DB_PORT` in the git-ignored `.env.test.local` file. Dotenv does not load `.env.local` in the test environment. The test database defaults to `retail_test_project_rails_test`; override it with `DB_TEST_NAME` only for a separate test database. The configured PostgreSQL role must own that database and have `CREATEDB`, because Rails recreates it when preparing the test schema.

```bash
RAILS_ENV=test bin/rails db:prepare
bin/rails test
```

### Importing Tracking Events

To import the million-row CSV file:
```bash
bin/rails tracking_events:import
```

The command first counts CSV records, then displays a progress bar with processed,
staged, and skipped row counts, plus elapsed seconds (including the counting pass).
The display updates after each batch and on completion. Inserts run in batches of 10,000 inside one transaction;
100% is displayed after the transaction succeeds. If the import fails, its changes
are rolled back. Rows with missing stores or products are skipped.
The progress display adapts to terminal width, using fewer details in narrow
windows so updates stay on a single line.

## Objectives

### First Objective: Price Tracking

Currently, the system only tracks if inventory is present via `TrackingEvent`. We want to add a way to track price. An inventory check and price check are separate and can occur without the other happening.

Tracking events use event-specific JSON in `value`:

- `inventory_presence`: `{ "present": false }` (requires a JSON boolean; both `true` and `false` are valid).
- `price_tracker`: `{ "amount": 12.50, "currency": "USD" }` (requires a nonnegative JSON number and a three-letter uppercase currency code).

Rails validations and PostgreSQL check constraints enforce these rules, including for bulk inserts. Currency validation checks the code format, not membership in an ISO currency registry. Payloads have no default: callers must supply an observation. The payload migration converts legacy boolean inventory values and fails atomically if existing records cannot meet the constraints; it does not invent missing observations or prices. This data conversion is irreversible through `db:rollback`.

Retrieve the current observations independently for a store/product pair:

```ruby
inventory = TrackingEvent.latest_inventory(store_id: store.id, product_id: product.id)
price = TrackingEvent.latest_price(store_id: store.id, product_id: product.id)
```

Each lookup returns an event or `nil` and filters by its own event category. Results are ordered by `event_time DESC, id DESC`: an older observation imported later cannot replace a newer one, and the greater ID breaks ties at identical observation times. Undated events remain in history but are excluded from current observations. A B-tree index on `(store_id, product_id, event_type, event_time DESC, id DESC)` supports these lookups; they do not search JSON contents and need no GIN index.

### Second Objective: Alert System

Build an alert system that creates an alert to the brand if a store has two "no inventory" events in a row for the same product based on event_time. There doesn't need to be a big UI for this—just a basic index and show page like the rest of the app.

### Third Objective: Performance Improvements

Improve the app's overall performance. This can be done as you work on the first and second objectives or after completing them.

## Technology Stack

- **Ruby**: 3.4.11
- **Rails**: 7.1.6
- **Database**: PostgreSQL 13+

## Evaluation Criteria

You will be evaluated on:
- Code quality and organization
- Database design decisions
- Performance optimizations
- Ability to explain your thinking and decision making

Feel free to make reasonable assumptions where requirements are ambiguous—just document them in your code or a separate notes file.

## Time Expectation

This project should take approximately [2-3 hours] to complete. Focus on demonstrating your problem-solving approach rather than achieving perfection. AI is allowed on this project. 

## Submission

Please submit:
- A link or invite to your Git repository (GitHub, GitLab, etc.)
- A brief README or notes document explaining your key decisions
- Any instructions needed to run your solution
