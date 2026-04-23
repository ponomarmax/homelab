# cAdvisor Config

cAdvisor is expected to stay mostly stateless.

Future checkpoints should keep the service lightweight and expose only the metrics needed by Prometheus.
Do not add extra configuration unless it solves a concrete operational need.
