{
  "family": "__TASK_FAMILY__",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX"
  },
  "executionRoleArn": "__EXEC_ROLE_ARN__",
  "taskRoleArn": "__TASK_ROLE_ARN__",
  "containerDefinitions": [
    {
      "name": "web",
      "image": "__IMAGE__",
      "essential": true,
      "portMappings": [
        {
          "containerPort": __APP_PORT__,
          "protocol": "tcp"
        }
      ],
      "environment": [
        { "name": "APP_VERSION", "value": "__IMAGE_TAG__" }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:__APP_PORT__/health', timeout=2).status==200 else 1)\""],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 10
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "__LOG_GROUP__",
          "awslogs-region": "__AWS_REGION__",
          "awslogs-stream-prefix": "web"
        }
      }
    }
  ]
}
