resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = "fluentbit"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_v1" "this" {
  metadata {
    name = "fluent-bit-read"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "nodes", "nodes/proxy"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "this" {
  metadata {
    name = "fluent-bit-read"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.this.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.this.metadata[0].name
    namespace = kubernetes_service_account_v1.this.metadata[0].namespace
  }
}

locals {
  daemon_set_labels = {
    "component" = "fluentbit-gke"
    "k8s-app"   = "fluentbit-gke"
  }
}

resource "kubernetes_daemon_set_v1" "this" {
  metadata {
    name      = "fluentbit"
    namespace = "kube-system"
    labels = {
      "k8s-app" = "fluentbit-gke"
    }
  }

  spec {
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 1
      }
    }

    selector {
      match_labels = local.daemon_set_labels
    }

    template {
      metadata {
        annotations = {
          "EnableNodeJournal"                   = "false"
          "EnablePodSecurityPolicy"             = "false"
          "SystemOnlyLogging"                   = "false"
          "components.gke.io/component-name"    = "fluentbit"
          "components.gke.io/component-version" = "1.7.4"
          "monitoring.gke.io/path"              = "/api/v1/metrics/prometheus"
        }
        labels = merge(local.daemon_set_labels, {
          "kubernetes.io/cluster-service" = "true"
        })
      }

      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "cloud.google.com/gke-max-pods-per-node"
                  operator = "DoesNotExist"
                }
                match_expressions {
                  key      = "cloud.google.com/gke-logging-variant"
                  operator = "NotIn"
                  values   = ["MAX_THROUGHPUT"]
                }
              }
              node_selector_term {
                match_expressions {
                  key      = "cloud.google.com/gke-max-pods-per-node"
                  operator = "Lt"
                  values   = ["111"]
                }
                match_expressions {
                  key      = "cloud.google.com/gke-logging-variant"
                  operator = "NotIn"
                  values   = ["MAX_THROUGHPUT"]
                }
              }
            }
          }
        }

        container {
          name              = "fluentbit"
          image             = "gke.gcr.io/fluent-bit:v1.8.7-gke.1"
          image_pull_policy = "IfNotPresent"

          liveness_probe {
            failure_threshold = 3
            http_get {
              path   = "/"
              port   = 2020
              scheme = "HTTP"
            }
            initial_delay_seconds = 120
            period_seconds        = 60
            success_threshold     = 1
            timeout_seconds       = 5
          }

          port {
            container_port = 2020
            host_port      = 2020
            name           = "metrics"
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "100Mi"
            }
            limits = {
              memory = "250Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              add  = ["DAC_OVERRIDE"]
              drop = ["all"]
            }
          }

          termination_message_path   = "/dev/termination-log"
          termination_message_policy = "File"

          volume_mount {
            mount_path = "/var/run/google-fluentbit/pos-files"
            name       = "varrun"
          }
          volume_mount {
            mount_path = "/var/log"
            name       = "varlog"
          }
          volume_mount {
            mount_path = "/var/lib/kubelet/pods"
            name       = "varlibkubeletpods"
          }
          volume_mount {
            mount_path = "/var/lib/docker/containers"
            name       = "varlibdockercontainers"
            read_only  = true
          }
          volume_mount {
            mount_path = "/fluent-bit/etc/"
            name       = "config-volume"
          }
        }

        container {
          name              = "fluentbit-gke"
          image             = "gke.gcr.io/fluent-bit-gke-exporter:v0.17.1-gke.0"
          image_pull_policy = "IfNotPresent"
          command = [
            "/fluent-bit-gke-exporter",
            "--kubernetes-separator=_",
            "--stackdriver-resource-model=k8s",
            "--enable-pod-label-discovery",
            "--pod-label-dot-replacement=_",
            "--split-stdout-stderr",
            "--stackdriver-timeout=60s",
            "--logtostderr",
          ]

          liveness_probe {
            failure_threshold = 3
            http_get {
              path   = "/healthz"
              port   = 2021
              scheme = "HTTP"
            }
            initial_delay_seconds = 120
            period_seconds        = 60
            success_threshold     = 1
            timeout_seconds       = 15
          }

          port {
            name           = "metrics"
            container_port = 2021
            host_port      = 2021
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "100Mi"
            }
            limits = {
              memory = "250Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["all"]
            }
            run_as_group = 1000
            run_as_user  = 1000
          }

          termination_message_path   = "/dev/termination-log"
          termination_message_policy = "File"
        }

        dns_policy   = "Default"
        host_network = true

        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        priority_class_name = "system-node-critical"
        restart_policy      = "Always"

        service_account_name = kubernetes_service_account_v1.this.metadata[0].name

        termination_grace_period_seconds = 120

        toleration {
          effect   = "NoExecute"
          operator = "Exists"
        }

        toleration {
          effect   = "NoSchedule"
          operator = "Exists"
        }

        toleration {
          key      = "components.gke.io/gke-managed-components"
          operator = "Exists"
        }

        volume {
          name = "varrun"
          host_path {
            path = "/var/run/google-fluentbit/pos-files"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibkubeletpods"
          host_path {
            path = "/var/lib/kubelet/pods"
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "config-volume"
          config_map {
            default_mode = "0420"
            name         = kubernetes_config_map_v1.this.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = "fluentbit-config"
    namespace = "kube-system"
  }

  data = {
    "parsers.conf" = <<-EOT
    [PARSER]
        Name        nginx
        Format      regex
        Regex       ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")
        Time_Key    time
        Time_Format %d/%b/%Y:%H:%M:%S %z

    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z

    [PARSER]
        Name        containerd
        Format      regex
        Regex       ^(?<time>.+) (?<stream>stdout|stderr) [^ ]* (?<log>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z

    [PARSER]
        Name        json
        Format      json

    [PARSER]
        Name        syslog
        Format      regex
        Regex       ^\<(?<pri>[0-9]+)\>(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$
        Time_Key    time
        Time_Format %b %d %H:%M:%S

    [PARSER]
        Name        glog
        Format      regex
        Regex       ^(?<severity>\w)(?<time>\d{4} [^\s]*)\s+(?<pid>\d+)\s+(?<source_file>[^ \]]+)\:(?<source_line>\d+)\]\s(?<message>.*)$
        Time_Key    time
        Time_Format %m%d %H:%M:%S.%L%z

    [PARSER]
        Name        network-log
        Format      json
        Time_Key    timestamp
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    EOT

    "fluent-bit.conf" = <<-EOT
    [SERVICE]
        Flush         5
        Grace         120
        Log_Level     info
        Log_File      /var/log/fluentbit.log
        Daemon        off
        Parsers_File  parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_PORT     2020


    [INPUT]
        Name             tail
        Alias            kube_containers_kube-system
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        (?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<namespace_name>[^_]+)_(?<container_name>.+)-
        Path             /var/log/containers/*_kube-system_*.log
        DB               /var/run/google-fluentbit/pos-files/flb_kube_kube-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    5MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            kube_containers_istio-system
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        (?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<namespace_name>[^_]+)_(?<container_name>.+)-
        Path             /var/log/containers/*_istio-system_*.log
        DB               /var/run/google-fluentbit/pos-files/flb_kube_istio-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    5MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            kube_containers_knative-serving
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        (?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<namespace_name>[^_]+)_(?<container_name>.+)-
        Path             /var/log/containers/*_knative-serving_*.log
        DB               /var/run/google-fluentbit/pos-files/flb_kube_knative-serving.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    5MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            kube_containers_gke-system
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        (?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<namespace_name>[^_]+)_(?<container_name>.+)-
        Path             /var/log/containers/*_gke-system_*.log
        DB               /var/run/google-fluentbit/pos-files/flb_kube_gke-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    5MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            kube_containers_config-management-system
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        (?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<namespace_name>[^_]+)_(?<container_name>.+)-
        Path             /var/log/containers/*_config-management-system_*.log
        DB               /var/run/google-fluentbit/pos-files/flb_kube_config-management-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    5MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True



    [INPUT]
        Name             tail
        Alias            kube_containers
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        (?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<namespace_name>[^_]+)_(?<container_name>.+)-
        Path             /var/log/containers/*.log
        Exclude_Path     /var/log/containers/*_kube-system_*.log,/var/log/containers/*_istio-system_*.log,/var/log/containers/*_knative-serving_*.log,/var/log/containers/*_gke-system_*.log,/var/log/containers/*_config-management-system_*.log
        DB               /var/run/google-fluentbit/pos-files/flb_kube.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    5MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True


    # This input plugin is used to collect the logs located inside the /var/log
    # directory of a Cloud Run on GKE / Knative container. Knative mounts
    # an emptyDir volume named 'knative-var-log' inside the user container and
    # if collection is enabled it creates a symbolic link inside another
    # emptyDir named 'knative-internal' that contains the information needed for
    # Kubernetes metadata enrichment.
    #
    # Concretely, on the host the symbolic link is:
    # /var/lib/kubelet/pods/<POD_ID>/volumes/kubernetes.io~empty-dir/knative-internal/<NAMESPACE_NAME>_<POD_NAME>_<CONTAINER_NAME>
    # ->
    # /var/lib/kubelet/pods/<POD_ID>/volumes/kubernetes.io~empty-dir/knative-var-log
    [INPUT]
        Name             tail
        Alias            knative
        Tag              kube_<namespace_name>_<pod_name>_<container_name>
        Tag_Regex        \/var\/lib\/kubelet\/pods\/.+\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Path             /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/knative-internal/**/*/**/*
        DB               /var/run/google-fluentbit/pos-files/knative.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [FILTER]
        Name         parser
        Match        kube_*
        Key_Name     log
        Reserve_Data True
        Parser       docker
        Parser       containerd

    # This input is used  to watch changes to Kubernetes pod log files live in the
    # directory /var/log/pods/NAMESPACE_NAME_UID. The file name is used to
    # capture the pod namespace, name and runtime name.


    [INPUT]
        Name             tail
        Alias            gvisor_kube-system
        Tag              kube-pod_<namespace_name>_<pod_name>_<runtime>
        Tag_Regex        \/var\/log\/pods\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Path             /var/log/pods/kube-system_*/*
        DB               /var/run/google-fluentbit/pos-files/gvisor_kube-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            gvisor_istio-system
        Tag              kube-pod_<namespace_name>_<pod_name>_<runtime>
        Tag_Regex        \/var\/log\/pods\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Path             /var/log/pods/istio-system_*/*
        DB               /var/run/google-fluentbit/pos-files/gvisor_istio-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            gvisor_knative-serving
        Tag              kube-pod_<namespace_name>_<pod_name>_<runtime>
        Tag_Regex        \/var\/log\/pods\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Path             /var/log/pods/knative-serving_*/*
        DB               /var/run/google-fluentbit/pos-files/gvisor_knative-serving.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            gvisor_gke-system
        Tag              kube-pod_<namespace_name>_<pod_name>_<runtime>
        Tag_Regex        \/var\/log\/pods\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Path             /var/log/pods/gke-system_*/*
        DB               /var/run/google-fluentbit/pos-files/gvisor_gke-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    [INPUT]
        Name             tail
        Alias            gvisor_config-management-system
        Tag              kube-pod_<namespace_name>_<pod_name>_<runtime>
        Tag_Regex        \/var\/log\/pods\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Path             /var/log/pods/config-management-system_*/*
        DB               /var/run/google-fluentbit/pos-files/gvisor_config-management-system.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True



    [INPUT]
        Name             tail
        Alias            gvisor
        Tag              kube-pod_<namespace_name>_<pod_name>_<runtime>
        Tag_Regex        \/var\/log\/pods\/(?<namespace_name>[^_]+)_(?<pod_name>[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)_(?<id>[\-a-z0-9]+)\/(?<runtime>[a-z]+)\.log
        Exclude_Path     /var/log/pods/kube-system_*/*,/var/log/pods/istio-system_*/*,/var/log/pods/knative-serving_*/*,/var/log/pods/gke-system_*/*,/var/log/pods/config-management-system_*/*
        Path             /var/log/pods/*/*.log
        DB               /var/run/google-fluentbit/pos-files/gvisor.db
        Buffer_Max_Size  1MB
        Mem_Buf_Limit    1MB
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True


    # Example:
    # Dec 21 23:17:22 gke-foo-1-1-4b5cbd14-node-4eoj startupscript: Finished running startup script /var/run/google.startup.script
    [INPUT]
        Name   tail
        Parser syslog
        Path   /var/log/startupscript.log
        DB     /var/run/google-fluentbit/pos-files/startupscript.db
        Alias  startupscript
        Tag    startupscript

    # Logs from anetd for policy action
    [INPUT]
        Name             tail
        Parser           network-log
        Alias            policy-action
        Tag              policy-action
        Path             /var/log/network/policy_action.log
        DB               /var/run/google-fluentbit/pos-files/policy-action.db
        Skip_Long_Lines  On
        Refresh_Interval 5
        Read_from_Head   True

    # Example:
    # I1118 21:26:53.975789       6 proxier.go:1096] Port "nodePort for kube-system/default-http-backend:http" (:31429/tcp) was open before and is still needed
    [INPUT]
        Name            tail
        Alias           kube-proxy
        Tag             kube-proxy
        Path            /var/log/kube-proxy.log
        DB              /var/run/google-fluentbit/pos-files/kube-proxy.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB
        Parser          glog
        Read_from_Head  True

    # Logs from systemd-journal for interesting services.

    [INPUT]
        Name            systemd
        Alias           docker
        Tag             docker
        Systemd_Filter  _SYSTEMD_UNIT=docker.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/docker.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           kubelet
        Tag             kubelet
        Systemd_Filter  _SYSTEMD_UNIT=kubelet.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/kubelet.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           kube-node-installation
        Tag             kube-node-installation
        Systemd_Filter  _SYSTEMD_UNIT=kube-node-installation.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/kube-node-installation.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           kube-node-configuration
        Tag             kube-node-configuration
        Systemd_Filter  _SYSTEMD_UNIT=kube-node-configuration.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/kube-node-configuration.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           kube-logrotate
        Tag             kube-logrotate
        Systemd_Filter  _SYSTEMD_UNIT=kube-logrotate.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/kube-logrotate.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           node-problem-detector
        Tag             node-problem-detector
        Systemd_Filter  _SYSTEMD_UNIT=node-problem-detector.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/node-problem-detector.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           kube-container-runtime-monitor
        Tag             kube-container-runtime-monitor
        Systemd_Filter  _SYSTEMD_UNIT=kube-container-runtime-monitor.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/kube-container-runtime-monitor.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           kubelet-monitor
        Tag             kubelet-monitor
        Systemd_Filter  _SYSTEMD_UNIT=kubelet-monitor.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/kubelet-monitor.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           gcfsd
        Tag             gcfsd
        Systemd_Filter  _SYSTEMD_UNIT=gcfsd.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/gcfsd.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB

    [INPUT]
        Name            systemd
        Alias           gcfs-snapshotter
        Tag             gcfs-snapshotter
        Systemd_Filter  _SYSTEMD_UNIT=gcfs-snapshotter.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/gcfs-snapshotter.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB


    [INPUT]
        Name            systemd
        Alias           container-runtime
        Tag             container-runtime
        Systemd_Filter  _SYSTEMD_UNIT=containerd.service
        Path            /var/log/journal
        DB              /var/run/google-fluentbit/pos-files/container-runtime.db
        Buffer_Max_Size 1MB
        Mem_Buf_Limit   1MB


    [FILTER]
        Name        modify
        Match       *
        Hard_rename log message

    [FILTER]
        Name         parser
        Match        kube_*
        Key_Name     message
        Reserve_Data True
        Parser       glog
        Parser       nginx
        Parser       json

    # level is a common synonym for severity,
    # the default field name in libraries such as GoLang's zap.
    # populate severity with level, if severity does not exist.
    [FILTER]
        Name        modify
        Match       kube_*
        Copy        level severity

    [OUTPUT]
        Name        http
        Match       *
        Host        127.0.0.1
        Port        2021
        URI         /logs
        header_tag  FLUENT-TAG
        Format      msgpack
        Retry_Limit 2
    EOT
  }
}
