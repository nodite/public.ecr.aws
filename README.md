
https://docs.aws.amazon.com/AmazonECR/latest/public/getting-started-cli.html

```
aws ecr-public create-repository \
  --repository-name <repository> \
  --catalog-data file://catalog.json \
  --region us-east-1 \
  --profile me.oscaner
```
