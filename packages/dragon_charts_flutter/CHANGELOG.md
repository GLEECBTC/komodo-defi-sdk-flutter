## 0.1.1-dev.4

 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**: add configurable sparkline baseline (#248).

## 0.1.1-dev.3

> Note: This release has breaking changes.

 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.
 - **FEAT**: allow sparkline charts to customize the baseline calculation for positive/negative value classification, defaulting to the initial value.

## 0.1.1-dev.2

> Note: This release has breaking changes.

- **FEAT**(rpc): trading-related RPCs/types (#191).
- **FEAT**(auth): poll trezor connection status and sign out when disconnected (#126).
- **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 0.0.1-pre1 (2024-05-26)

- First stable MVP PoC with line graphs implemented.

## 0.0.1 (2024-05-26)

- Visual improvements to the line graphs and tooltips.
- Partial API documentation.
- Improvements to animations, especially when changing data set size.
- Other miscellaneous bug fixes and improvements.

## 0.0.2 - 2024-06-17

### Added

- **Minor visual tweaks**: Improved the visual appearance of the application with minor tweaks for better user experience. (`2fc0171e`)
- **QoL improvements and miscellaneous changes**: Added various quality-of-life improvements and miscellaneous changes for better functionality and user experience. (`f2c39896`)
- **Multiple point selection/highlighting strategies**: Introduced new strategies for selecting and highlighting multiple points on the chart, enhancing interactivity. (`bb94c136`)

### Changed

- **Cartesian selection configuration**: Enhanced the configuration options for cartesian selection, providing more flexibility and customization options. (`dc49710f`)
- **Tooltip functionality**: Improved the tooltip functionality, ensuring accurate and clear information display. (`b44b0833`)

### Fixed

- **Further lint fixes**: Addressed additional linting issues to maintain code quality and consistency. (`7231300c`)
- **Chart padding for labels**: Fixed padding issues to ensure labels are correctly displayed without overlapping, improving chart readability. (`344c2014`)

### Documentation

- **Rename reference of Graph to Chart**: Refactored code to rename references from `Graph` to `Chart` for better clarity and consistency. (`6a790fbb`)
- **README updates**:
  - Updated references from `GraphExtent` to `ChartExtent`.
  - Improved documentation for chart components and their properties.

## 0.0.3 - 2024-07-01

### Added

- **Sparkline Chart**: Added support for sparkline charts, allowing users to visualize data trends in a compact format. (`8124e08`)

## 0.1.0 - 2024-07-05

- **Initial release with support for line charts.**: The first stable release of the library, providing support for line charts. No functional changes from the previous version.
- **Linter Fixes**: Apply linter fixes. There are no functional changes.
