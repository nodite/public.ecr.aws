
https://docs.aws.amazon.com/AmazonECR/latest/public/getting-started-cli.html

```
aws ecr-public get-login-password --region us-east-1 --profile me.oscaner | \
  docker login --username AWS --password-stdin public.ecr.aws
```

```
aws ecr-public create-repository \
  --repository-name <repository> \
  --catalog-data file://catalog.json \
  --region us-east-1 \
  --profile me.oscaner
```

```
aws ecr-public put-repository-catalog-data \
  --repository-name <repository> \
  --catalog-data file://catalog.json \
  --region us-east-1 \
  --profile me.oscaner
```
