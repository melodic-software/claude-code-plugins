## Purpose

Claude Code budgets the model-visible skill listing at a fraction of the context
window (`skillListingBudgetFraction`, default 0.01) and, when it overflows,
**drops descriptions starting with the skills you invoke least**. Names always
survive, descriptions do not. A skill at zero usage therefore loses its
description, loses the keywords a request would match against, and stays at
zero. Unused is partly self-causing, and the loop is documented.
