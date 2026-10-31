# Information architecture terms

How content is structured and found. Each entry gives the term, a definition, and the line between
it and the term most often confused with it.

## Information Architecture: `information-architecture`

### Progressive disclosure: `progressive-disclosure`

Showing only what is needed at each step, revealing complexity as the user goes deeper. The opposite
is putting everything on one page.

**Versus:** hierarchy ranks what is shown; progressive disclosure decides when more is shown.

### Mental model: `mental-model`

The user's internal picture of how something works. Good IA matches it. When it does not, users get
lost and blame themselves.

**Versus:** a mental model is the user's picture; the information architecture is the structure the
product actually has.

### Empty state: `empty-state`

The view when there is no content yet. Should explain why and offer a next step. No data ends the
journey.

**Versus:** Empty state in `components.md` is the same view seen as a component; an error state is a
failure, not an absence of content.

### Onboarding: `onboarding`

Introducing a new user to a product. The best onboarding delivers value immediately. A user who
completes one meaningful action is more likely to return than one who watched a tour.

**Versus:** an empty state helps at one view with no content; onboarding introduces the whole
product.

### Wayfinding: `wayfinding`

The system of signals that help users understand where they are, how they got there, and where they
can go. Breadcrumbs, active states in navigation, page titles, and URL structure all contribute.
When wayfinding breaks down, users feel lost without being able to say why.

**Versus:** a signpost is one orienting element; wayfinding is the whole system of them. Navigation
is how users move; wayfinding is how they know where they are.

### Labeling: `labeling`

The words used for navigation items, section headers, and categories.

**Versus:** microcopy covers all short interface text; labeling is the words used for navigation and
categories.

### Search as escape hatch: `search-as-escape-hatch`

When users resort to search because navigation has failed them. High search volume for things that
should be findable by browsing is a signal the IA needs work, not that search needs to be better.

**Versus:** search as a primary tool is chosen; search as an escape hatch is the fallback when
browsing fails.

### Card sorting: `card-sorting`

A research method where users group topics or features into categories that make sense to them. Used
to validate or challenge IA decisions before building. Reveals the gap between how designers label
things and how users think about them.

**Versus:** a tree test checks whether users can find items in a structure; card sorting asks them
to build the structure.

### Navigation: `navigation`

The system for moving between areas of a product. Labels should match how users describe things, not
internal terminology.

**Versus:** Navigation menu in `components.md` is the component; navigation is the whole system of
moving between areas. Wayfinding is how users know where they are.

### Hierarchy: `hierarchy`

The ranking of elements by importance. Without it, everything competes and nothing wins.

**Versus:** depth counts the levels to reach content; hierarchy ranks elements by importance.

### Error state: `error-state`

What the UI shows when something fails. Should say what went wrong and offer a specific way to
recover.

**Versus:** an error message is the text; an error state is the whole view the failure produces. An
empty state is an absence, not a failure.

### Confirmation dialog: `confirmation-dialog`

A prompt before a destructive or irreversible action. Should describe what will be lost, not just
ask are you sure. Keep the destructive and safe actions visually far apart.

**Versus:** Modal / dialog in `components.md` is the overlay component; a confirmation dialog is one
use of it, before a destructive action.

### Signpost: `signpost`

A UI element whose only job is to orient the user: a section header, a category label, a step
indicator. Good signposts are invisible when working. They only become noticeable when missing.

**Versus:** wayfinding is the whole system; a signpost is one element in it.

### Depth: `depth`

How many levels of navigation a user must traverse to reach content.

**Versus:** hierarchy ranks elements by importance; depth counts the navigation levels to reach
content.

### Content inventory: `content-inventory`

A complete list of everything in a product or site, used to identify gaps, duplicates, and orphaned
pages before restructuring.

**Versus:** a content audit judges each item's quality; a content inventory only lists everything
there is.
