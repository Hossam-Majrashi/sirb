# Sirb — design decisions

1. The primary action is opening and watching real websites while rapidly switching among many tabs.
2. There is no AI component; browser and resource management remain deterministic and local.
3. The address/navigation bar, active website, and collapsible vertical tab rail remain visible.
4. History, downloads, find, resource controls, and preferences appear only when requested.
5. A browser workspace with a vertical tab rail is selected because titles remain legible with 100 tabs. A centered task-card launcher was rejected because it displaces the website; a horizontal-only tab strip was rejected because dozens of titles become unreadable.
6. Desktop uses keyboard shortcuts, drag reordering, context menus, and a collapsible rail below 1000 pixels. Settings and onboarding have constrained content widths. Mobile and web are not targets and no layouts or platform folders are created for them.
