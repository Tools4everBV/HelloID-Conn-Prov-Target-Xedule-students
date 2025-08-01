# HelloID-Conn-Prov-Target-Xedule-students

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://partner.afas.nl/file/download/default/F2DF898CDDD64CD4A9CCD9A15B2262A8/Xedule-logomark-pos.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Xedule-students](#helloid-conn-prov-target-xedule-students)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported  features](#supported--features)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Xedule-students_ is a _target_ connector. _Xedule-students_ provides a set of REST API's that allow you to programmatically interact with its data.

## Supported  features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks |
| ----------------------------------------- | --------- | --------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ❌         | -                                       |         |
| **Resources**                             | ❌         | -                                       |         |
| **Entitlement Import: Accounts**          | ✅         | -                                       |         |
| **Entitlement Import: Permissions**       | ❌         | -                                       |         |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |         |

## Getting started

### Prerequisites

- The information from the Connection setting Table: [Connection settings](#connection-settings)

### Connection settings

The following settings are required to connect to the API.

| Setting                | Description                                      | Mandatory |
| ---------------------- | ------------------------------------------------ | --------- |
| OreId                  | The OreId to connect to the API                  | Yes       |
| Customer               | The Customer to connect to the API               | Yes       |
| OcpApimSubscriptionKey | The OcpApimSubscriptionKey to connect to the API | Yes       |
| BaseUrl                | The URL to the API                               | Yes       |
| TenantId               | The TenantId to connect to the API               | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Xedule-students_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `ReferentieID`                    |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from _Xedule-students_

## Remarks
Current state of the connector:
- The property Studeert is used to enable and disable accounts. It is not clear how this is used. More information has been requested from the supplier/customer.
- The connector is DryCoded and will be further developed once a working test environment is available.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                                                             | Description                              |
| ------------------------------------------------------------------------------------ | ---------------------------------------- |
| /students-groups/api/Student/ore/:oreId?customer=:Customer                           | Retrieve user information by referenceId |
| /students-groups/api/Student/ore/:oreId/referenceKey/:referenceId?customer=:Customer | CRUD user actions                        |
| /students-groups/api/Student/ore/:oreId/id/:id?customer=:Customer                    | Retrieve user information by Id          |

### API documentation

https://developer.connect.xedule.nl/api-details#api=students-groups-prod&operation=Student_GetStudenten

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
