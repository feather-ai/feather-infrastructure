[
    {
      "essential": true,
      "memory": 384,
      "name": "ftr-service-core",
      "cpu": 1,
      "image": "${repository_rul}:latest",
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 8080
        }
      ],
      "environment": [
        {
          "name": "DATABASE_URL",
          "value": "${db_url}"
        },
        {
          "name": "PORT",
          "value": "8080"
        },
        {
          "name": "AWS_REGION",
          "value": "us-east-2"
        },
        {
          "name": "DEBUG_USER",
          "value": "${debug_user}"
        },
        {
          "name": "AWS_ACCESS_KEY_ID",
          "value": "${aws_access_key_id}"
        },
        {
          "name": "AWS_SECRET_ACCESS_KEY",
          "value": "${aws_secret_access_key}"
        },
        {
          "name": "STRIPE_WEBHOOK_SECRET_KEY",
          "value": "${stripe_webhook_secret_key}"
        },
        {
          "name": "STRIPE_SECRET_KEY",
          "value": "${stripe_secret_key}"
        },
        {
          "name": "MODEL_JWT_SIGNING_SECRET",
          "value": "${model_jwt_secret_key}"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "service-core",
          "awslogs-region": "us-east-2",
          "awslogs-stream-prefix": "ftr"
        }
      }
    }
]