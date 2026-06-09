<template>
  <div class="addresses-page">
    <div class="page-header">
      <h2 class="page-title">收货地址</h2>
      <el-button type="primary" :icon="Plus" @click="openDialog()">新增地址</el-button>
    </div>

    <div v-loading="loading" class="addr-list">
      <template v-if="addresses.length > 0">
        <el-card v-for="addr in addresses" :key="addr.id" class="addr-card" shadow="hover">
          <div class="addr-body">
            <div class="addr-top">
              <span class="receiver">{{ addr.receiver }}</span>
              <span class="phone">{{ addr.phone }}</span>
              <el-tag v-if="addr.isDefault" type="success" size="small" effect="plain">默认</el-tag>
            </div>
            <div class="addr-text">{{ addr.province }} {{ addr.city }} {{ addr.district }} {{ addr.detail }}</div>
          </div>
          <div class="addr-actions">
            <el-button text size="small" @click="openDialog(addr)">编辑</el-button>
            <el-button
              v-if="!addr.isDefault"
              text
              size="small"
              @click="handleSetDefault(addr.id)"
            >设为默认</el-button>
            <el-popconfirm
              title="确认删除该地址？"
              confirm-button-text="确认删除"
              cancel-button-text="取消"
              @confirm="handleDelete(addr.id)"
            >
              <template #reference>
                <el-button text size="small" type="danger">删除</el-button>
              </template>
            </el-popconfirm>
          </div>
        </el-card>
      </template>
      <el-empty v-else-if="!loading" description="暂无收货地址，点击右上角新增">
        <el-button type="primary" @click="openDialog()">新增地址</el-button>
      </el-empty>
    </div>

    <!-- 新增 / 编辑地址弹窗 -->
    <el-dialog
      v-model="dialogVisible"
      :title="editId ? '编辑地址' : '新增地址'"
      width="500px"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="rules" label-width="90px">
        <el-form-item label="收货人" prop="receiver">
          <el-input v-model="form.receiver" placeholder="请填写收货人姓名" maxlength="20" />
        </el-form-item>
        <el-form-item label="手机号" prop="phone">
          <el-input v-model="form.phone" placeholder="11位手机号码" maxlength="11" />
        </el-form-item>
        <el-form-item label="省 / 市 / 区" prop="region">
          <el-cascader
            v-model="form.region"
            :options="pcaOptions"
            style="width: 100%"
            placeholder="请选择省 / 市 / 区"
            filterable
          />
        </el-form-item>
        <el-form-item label="详细地址" prop="detail">
          <el-input
            v-model="form.detail"
            type="textarea"
            :rows="2"
            placeholder="街道、楼栋、门牌号等"
            maxlength="100"
            show-word-limit
          />
        </el-form-item>
        <el-form-item label="">
          <el-checkbox v-model="form.isDefault">设为默认地址</el-checkbox>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleSubmit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import pcaData from '@/assets/pca.json'
import {
  getUserAddresses,
  createAddress,
  updateAddress,
  deleteAddress,
  setDefaultAddress,
} from '@/api/address'

const pcaOptions = pcaData

const addresses    = ref([])
const loading      = ref(false)
const dialogVisible = ref(false)
const editId       = ref(null)
const submitting   = ref(false)
const formRef      = ref(null)

const emptyForm = () => ({
  receiver: '',
  phone: '',
  region: [],
  detail: '',
  isDefault: false,
})
const form = ref(emptyForm())

const rules = {
  receiver: [{ required: true, message: '请填写收货人姓名', trigger: 'blur' }],
  phone: [
    { required: true, message: '请填写手机号', trigger: 'blur' },
    { pattern: /^1[3-9]\d{9}$/, message: '手机号格式不正确', trigger: 'blur' },
  ],
  region: [
    { type: 'array', required: true, message: '请选择省 / 市 / 区', trigger: 'change' },
  ],
  detail: [{ required: true, message: '请填写详细地址', trigger: 'blur' }],
}

async function fetchAddresses() {
  loading.value = true
  try {
    addresses.value = await getUserAddresses()
  } finally {
    loading.value = false
  }
}

onMounted(fetchAddresses)

function openDialog(addr = null) {
  if (addr) {
    editId.value = addr.id
    form.value = {
      receiver: addr.receiver,
      phone: addr.phone,
      region: [addr.province, addr.city, addr.district],
      detail: addr.detail,
      isDefault: addr.isDefault,
    }
  } else {
    editId.value = null
    form.value = emptyForm()
  }
  dialogVisible.value = true
}

async function handleSubmit() {
  if (!formRef.value) return
  try {
    await formRef.value.validate()
  } catch {
    return
  }
  submitting.value = true
  try {
    const payload = {
      receiver: form.value.receiver,
      phone: form.value.phone,
      province: form.value.region[0],
      city: form.value.region[1],
      district: form.value.region[2],
      detail: form.value.detail,
      isDefault: form.value.isDefault,
    }
    if (editId.value) {
      await updateAddress(editId.value, payload)
      ElMessage.success('地址已更新')
    } else {
      await createAddress(payload)
      ElMessage.success('地址已添加')
    }
    dialogVisible.value = false
    fetchAddresses()
  } catch (err) {
    ElMessage.error(err.message || '操作失败')
  } finally {
    submitting.value = false
  }
}

async function handleDelete(id) {
  try {
    await deleteAddress(id)
    ElMessage.success('地址已删除')
    fetchAddresses()
  } catch (err) {
    ElMessage.error(err.message || '删除失败')
  }
}

async function handleSetDefault(id) {
  try {
    await setDefaultAddress(id)
    ElMessage.success('已设为默认地址')
    fetchAddresses()
  } catch (err) {
    ElMessage.error(err.message || '设置失败')
  }
}
</script>

<style scoped>
.addresses-page {
  max-width: 760px;
  margin: 32px auto;
  padding: 0 16px;
}
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 24px;
}
.page-title {
  font-size: 22px;
  font-weight: 600;
  margin: 0;
}
.addr-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.addr-card {
  border-radius: 8px;
}
.addr-card :deep(.el-card__body) {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 20px;
}
.addr-body {
  flex: 1;
}
.addr-top {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 6px;
}
.receiver {
  font-size: 15px;
  font-weight: 600;
  color: #303133;
}
.phone {
  font-size: 14px;
  color: #606266;
}
.addr-text {
  font-size: 13px;
  color: #909399;
  line-height: 1.5;
}
.addr-actions {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
}
</style>
