# ``TrainingTools``

Provider-neutral tool registry, JSON schema generation, and the plan sandbox for LLM-driven coaching.

## Overview

`TrainingTools` depends on `TrainingCore` and is available on all supported platforms. It defines a provider-neutral tool registry and JSON schemas, plus the `PlanSandbox` mutation seam that lets an LLM coach propose plan changes without touching the committed stores directly. `TrainingToolsAnthropic` and `TrainingToolsFoundationModels` adapt this registry to specific model providers.

## Topics

### Overview

- ``TrainingTools``
