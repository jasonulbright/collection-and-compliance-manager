# Glossary

This page defines the terms of Collection and Compliance Manager.

## What it does

It explains the terms that the tool and this guide use.

## When to use it

Use it when a term is not clear.

## Requirements

None.

## Terms

| Term | Meaning |
|---|---|
| Device collection | A group of devices on the site. It has a limiting collection and rules. |
| Limiting collection | The collection that limits which devices a collection can hold. |
| Built-in collection | A collection that the site makes. Its ID starts with `SMS`. |
| Direct member | A device that you add to a collection by name. |
| Query rule | A WQL query that adds devices to a collection. |
| Include rule, exclude rule | A rule that adds or removes the members of another collection. |
| WQL | The query language of the site. |
| Template | A ready-made query. An operational template is fixed. A parameterized template has parameters. |
| CI | Configuration item. It holds settings that a device must meet. |
| CB | Configuration baseline. It groups CIs and is deployed to collections. |
| Catalog | The bundled set of CI and CB entries with a builder for each. |
| ccm tag | The text `[ccm:<id>@<version>]` that the tool writes in a baseline that it deployed. |
| Drift | The deployed version of a baseline differs from the catalog version. |
| SMS Provider | The server role that gives access to the site data. |

## Steps

None.

## Limits

None.

## Troubleshooting

None.

## Links

- [Collections](../core/collections.md)
