
https://docs.aws.amazon.com/AmazonECR/latest/public/getting-started-cli.html

```
aws ecr-public get-login-password --region us-east-1 --profile me.oscaner | \
  docker login --username AWS --password-stdin public.ecr.aws
```
